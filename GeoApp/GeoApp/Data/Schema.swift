import Foundation
import GeoCore
import OSLog
import SwiftData

// Versionen des Speichers. Jede Änderung an einem Modell braucht eine neue Version und eine
// Migrationsstufe, sonst lässt sich ein bestehender Speicher nicht mehr öffnen.

/// Stand bis Oktober 2026: ein `VisitEvent` pro Ort, neu nach 6 Stunden.
/// Genaue Kopie der damaligen Modelle, damit SwiftData den alten Speicher erkennt. Nicht ändern.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Country.self, City.self, VisitEvent.self, DiagnosticEntry.self] }

    @Model
    final class Country {
        @Attribute(.unique) var isoCode: String
        var name: String
        var firstVisited: Date
        var lastVisited: Date

        init(isoCode: String, name: String, visited: Date) {
            self.isoCode = isoCode
            self.name = name
            self.firstVisited = visited
            self.lastVisited = visited
        }
    }

    @Model
    final class City {
        @Attribute(.unique) var geonamesId: Int
        var name: String
        var countryCode: String
        var centerLatitude: Double
        var centerLongitude: Double
        var firstVisited: Date
        var lastVisited: Date

        init(geonamesId: Int, name: String, countryCode: String, centerLatitude: Double, centerLongitude: Double,
             visited: Date) {
            self.geonamesId = geonamesId
            self.name = name
            self.countryCode = countryCode
            self.centerLatitude = centerLatitude
            self.centerLongitude = centerLongitude
            self.firstVisited = visited
            self.lastVisited = visited
        }
    }

    @Model
    final class VisitEvent {
        var id: UUID
        var timestamp: Date
        var geonamesId: Int?
        var countryCode: String
        var regionId: String?
        var districtId: String?
        var sourceRaw: String

        init(timestamp: Date, geonamesId: Int?, countryCode: String, source: CaptureSource,
             regionId: String? = nil, districtId: String? = nil) {
            self.id = UUID()
            self.timestamp = timestamp
            self.geonamesId = geonamesId
            self.countryCode = countryCode
            self.regionId = regionId
            self.districtId = districtId
            self.sourceRaw = source.rawValue
        }
    }

    @Model
    final class DiagnosticEntry {
        var timestamp: Date
        var sourceRaw: String
        var outcome: String
        var cityName: String?
        var districtName: String?
        var countryCode: String?
        var distanceToCityCenterKm: Double?

        init(timestamp: Date, source: CaptureSource, outcome: String) {
            self.timestamp = timestamp
            self.sourceRaw = source.rawValue
            self.outcome = outcome
        }
    }
}

/// Ein Eintrag pro Ort und Tag (`DayVisit`), Diagnose-Log mit Hinweis auf ungefähre Position.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Country.self, City.self, DayVisit.self, DiagnosticEntry.self] }
}

enum GeoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }

    /// Die Ereignisse aus V1 werden vor der Umstellung gelesen und danach zu Tagen zusammengefasst.
    /// Länder und Städte bleiben, wie sie sind.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self,
        willMigrate: { context in
            let events = try context.fetch(FetchDescriptor<SchemaV1.VisitEvent>())
            LegacyEvents.shared.store(events.map { event in
                DayVisits.Entry(day: VisitRules.dayKey(for: event.timestamp), countryCode: event.countryCode,
                                geonamesId: event.geonamesId, regionId: event.regionId, districtId: event.districtId,
                                timestamp: event.timestamp,
                                source: CaptureSource(rawValue: event.sourceRaw) ?? .manual)
            })
        },
        didMigrate: { context in
            let entries = LegacyEvents.shared.take()
            for entry in entries { DayVisits.add(entry, context: context) }
            try context.save()
            Logger(subsystem: "de.max.geoapp", category: "Daten")
                .info("Migration V1 → V2: \(entries.count) Ereignisse zu Tagen zusammengefasst")
        })
}

/// Übergabe der alten Ereignisse von `willMigrate` an `didMigrate`.
private nonisolated final class LegacyEvents: @unchecked Sendable {
    static let shared = LegacyEvents()
    private let lock = NSLock()
    private var entries: [DayVisits.Entry] = []

    func store(_ entries: [DayVisits.Entry]) {
        lock.withLock { self.entries = entries }
    }

    func take() -> [DayVisits.Entry] {
        lock.withLock {
            defer { entries = [] }
            return entries
        }
    }
}
