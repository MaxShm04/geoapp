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

    /// Gemeinsamer Container für Oberfläche und Hintergrund-Erfassung. Liegt in der App Group,
    /// damit Widgets und später die Watch an die Daten kommen (Phase 2, D7).
    static let shared: ModelContainer = {
        do {
            let opened = try makeContainer(legacy: StoreLocation.legacyURL, group: AppGroup.containerURL)
            log.info("Speicher geöffnet: \(String(describing: opened.outcome), privacy: .public)")
            return opened.container
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

    /// Öffnet den Speicher, zieht ihn vorher bei Bedarf in die App Group um (D7) und löscht den
    /// alten erst, wenn die Kopie geöffnet ist. Eine Kopie, die sich nicht öffnen lässt, wird entfernt.
    static func makeContainer(legacy: URL, group: URL?) throws
        -> (container: ModelContainer, url: URL, outcome: StoreLocation.Outcome) {
        let (url, outcome) = StoreLocation.resolve(legacy: legacy, group: group)
        do {
            let container = try open(at: url)
            if url != legacy, outcome == .moved || outcome == .alreadyMoved {
                StoreLocation.removeLegacy(at: legacy)
            }
            return (container, url, outcome)
        } catch {
            // Nur eine gerade angelegte Kopie wird verworfen, nie ein Speicher, der schon in Gebrauch war.
            guard outcome == .moved else { throw error }
            log.error("Kopie in der App Group lässt sich nicht öffnen, alter Ort bleibt: \(error.localizedDescription, privacy: .public)")
            StoreLocation.removeStore(at: url)
            return (try open(at: legacy), legacy, .failed(error.localizedDescription))
        }
    }

    private static func open(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ModelContainer(for: schema, migrationPlan: GeoMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, url: url))
    }

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
