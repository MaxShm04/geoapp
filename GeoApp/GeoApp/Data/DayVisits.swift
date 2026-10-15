import Foundation
import GeoCore
import SwiftData

/// Schreibt Tageseinträge (`DayVisit`): ein Eintrag pro Ort und Tag, weitere Erfassungen
/// werden hineingezählt. Erfassung, Migration und Angleichen der Städte laufen alle hier durch.
nonisolated enum DayVisits {
    /// Ein Tageseintrag als Wert, bevor er gespeichert oder mit einem vorhandenen zusammengeführt wird.
    struct Entry: Sendable {
        var day: Int
        var countryCode: String
        var geonamesId: Int?
        var regionId: String?
        var districtId: String?
        var firstSeen: Date
        var lastSeen: Date
        var captureCount = 1
        var sourceMask: Int
        var isDemo: Bool

        /// Tag, Land, Stadt, Gebiet (Kreis, sonst Region) und Herkunft.
        var key: String {
            [String(day), countryCode, geonamesId.map(String.init) ?? "-", districtId ?? regionId ?? "-",
             isDemo ? "demo" : "real"].joined(separator: "|")
        }

        /// Eine einzelne Erfassung.
        init(match: GeoMatch, timestamp: Date, source: CaptureSource, calendar: Calendar = .current) {
            self.init(day: VisitRules.dayKey(for: timestamp, calendar: calendar), countryCode: match.countryCode,
                      geonamesId: match.city?.id, regionId: match.regionId, districtId: match.districtId,
                      timestamp: timestamp, source: source)
        }

        init(day: Int, countryCode: String, geonamesId: Int?, regionId: String?, districtId: String?,
             timestamp: Date, source: CaptureSource) {
            self.day = day
            self.countryCode = countryCode
            self.geonamesId = geonamesId
            self.regionId = regionId
            self.districtId = districtId
            self.firstSeen = timestamp
            self.lastSeen = timestamp
            self.sourceMask = source.bit
            self.isDemo = source == .demo
        }

        /// Ein gespeicherter Eintrag als Wert, etwa um ihn einer anderen Stadt zuzuordnen.
        init(_ visit: DayVisit) {
            day = visit.day
            countryCode = visit.countryCode
            geonamesId = visit.geonamesId
            regionId = visit.regionId
            districtId = visit.districtId
            firstSeen = visit.firstSeen
            lastSeen = visit.lastSeen
            captureCount = visit.captureCount
            sourceMask = visit.sourceMask
            isDemo = visit.isDemo
        }

        mutating func merge(_ other: Entry) {
            firstSeen = min(firstSeen, other.firstSeen)
            lastSeen = max(lastSeen, other.lastSeen)
            captureCount += other.captureCount
            sourceMask |= other.sourceMask
        }
    }

    /// Legt den Eintrag an oder zählt ihn in den vorhandenen desselben Orts und Tags hinein.
    /// `isNew` ist wahr, wenn es den Ort an diesem Tag noch nicht gab.
    @discardableResult
    static func add(_ entry: Entry, context: ModelContext) -> (visit: DayVisit, isNew: Bool) {
        let key = entry.key
        var descriptor = FetchDescriptor<DayVisit>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            var merged = Entry(existing)
            merged.merge(entry)
            existing.firstSeen = merged.firstSeen
            existing.lastSeen = merged.lastSeen
            existing.captureCount = merged.captureCount
            existing.sourceMask = merged.sourceMask
            return (existing, false)
        }
        let visit = DayVisit(key: key, day: entry.day, countryCode: entry.countryCode, geonamesId: entry.geonamesId,
                             regionId: entry.regionId, districtId: entry.districtId,
                             firstSeen: entry.firstSeen, lastSeen: entry.lastSeen,
                             captureCount: entry.captureCount, sourceMask: entry.sourceMask, isDemo: entry.isDemo)
        context.insert(visit)
        return (visit, true)
    }

    /// Ordnet alle Tage einer Stadt einer anderen zu (oder nur dem Land bei `nil`). Gibt es den
    /// Zielort am selben Tag schon, werden die Einträge zusammengeführt.
    static func reassign(from oldID: Int, to newID: Int?, context: ModelContext) {
        let id: Int? = oldID
        let visits = (try? context.fetch(FetchDescriptor<DayVisit>(predicate: #Predicate { $0.geonamesId == id }))) ?? []
        for visit in visits {
            var entry = Entry(visit)
            entry.geonamesId = newID
            context.delete(visit)
            add(entry, context: context)
        }
    }
}
