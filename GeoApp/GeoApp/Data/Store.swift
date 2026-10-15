import Foundation
import GeoCore
import OSLog
import SwiftData

enum Store {
    static let schema = Schema(versionedSchema: SchemaV2.self)
    private static let log = Logger(subsystem: "de.max.geoapp", category: "Daten")

    /// Diagnose-Log: Einträge älter als das werden beim Start entfernt.
    static let diagnosticsMaxAge: TimeInterval = 14 * 86_400
    /// Diagnose-Log: höchstens so viele Einträge, die neuesten bleiben.
    static let diagnosticsMaxCount = 1000

    /// Fehler beim Öffnen des Speichers. Die App läuft dann mit einem leeren Speicher im
    /// Arbeitsspeicher weiter und zeigt den Fehler an. Die Datei auf dem Gerät bleibt unangetastet.
    private(set) static var openError: String?

    /// Gemeinsamer Container für Oberfläche und Hintergrund-Erfassung.
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: schema, migrationPlan: GeoMigrationPlan.self,
                                      configurations: ModelConfiguration(schema: schema))
        } catch {
            log.error("Speicher lässt sich nicht öffnen: \(error.localizedDescription, privacy: .public)")
            openError = error.localizedDescription
            do {
                return try inMemory()
            } catch {
                fatalError("Auch ein leerer Speicher lässt sich nicht anlegen: \(error)")
            }
        }
    }()

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: GeoMigrationPlan.self,
                           configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    /// Arbeit nach dem Start, ohne den Hauptthread zu blockieren: Geodaten im Hintergrund laden,
    /// gespeicherte Städte nur nach einem neuen Datenstand angleichen, Diagnose-Log kürzen.
    static func bootstrap(context: ModelContext = shared.mainContext, defaults: UserDefaults = .standard) async {
        let lookup = await Task.detached(priority: .userInitiated) { GeoLookup.shared }.value
        let version = GeoLookup.dataVersion
        if version == nil || defaults.string(forKey: AppSettings.dataVersion) != version {
            CityRemapping.run(context: context, lookup: lookup)
            defaults.set(version, forKey: AppSettings.dataVersion)
        }
        pruneDiagnostics(context: context)
    }

    static func pruneDiagnostics(context: ModelContext, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-diagnosticsMaxAge)
        do {
            try context.delete(model: DiagnosticEntry.self, where: #Predicate { $0.timestamp < cutoff })
            var surplus = FetchDescriptor<DiagnosticEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            surplus.fetchOffset = diagnosticsMaxCount
            try context.fetch(surplus).forEach(context.delete)
            try context.save()
        } catch {
            log.error("Diagnose-Log kürzen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }
}
