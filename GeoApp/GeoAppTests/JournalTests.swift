import Foundation
import GeoCore
import SwiftData
import Testing
@testable import GeoApp

/// Tagebuch-Adapter: `DayVisit` → `PlaceDay`, Heimatgebiet mit Einstellung, Reisen und Lückenfüllung.
@MainActor
struct JournalTests {
    private let captured = Date(timeIntervalSince1970: 1_780_000_000)

    /// Alle Tage von `start` bis `end` (yyyymmdd, beide eingeschlossen), gregorianisch in UTC.
    private func days(from start: Int, to end: Int) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100))!
        }
        func key(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return parts.year! * 10_000 + parts.month! * 100 + parts.day!
        }
        var result: [Int] = []
        var current = date(start)
        let last = date(end)
        while current <= last {
            result.append(key(current))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    /// Schreibt je Tag einen Eintrag für den Ort (Erfassung über `DayVisits.add`).
    private func addDays(_ days: [Int], country: String, cityId: Int?, regionId: String?, context: ModelContext) {
        for day in days {
            DayVisits.add(DayVisits.Entry(day: day, countryCode: country, geonamesId: cityId, regionId: regionId,
                                          districtId: nil, timestamp: captured, source: .visit), context: context)
        }
    }

    /// Munich, Verona und Rome als feste Orte der Testdaten.
    private func munich(_ days: [Int], _ context: ModelContext) {
        addDays(days, country: "DE", cityId: 2_867_714, regionId: "DE-BY", context: context)
    }

    private func verona(_ days: [Int], _ context: ModelContext) {
        addDays(days, country: "IT", cityId: 3_164_527, regionId: "IT-VEN", context: context)
    }

    private func rome(_ days: [Int], _ context: ModelContext) {
        addDays(days, country: "IT", cityId: 3_169_070, regionId: "IT-LAZ", context: context)
    }

    @Test func mapsDayVisits() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        DayVisits.add(DayVisits.Entry(day: 20_260_512, countryCode: "IT", geonamesId: 3_169_070, regionId: "IT-LAZ",
                                      districtId: nil, timestamp: captured, source: .visit), context: context)
        let visits = try context.fetch(FetchDescriptor<DayVisit>())
        let visit = try #require(visits.first)

        let place = PlaceDay(visit)
        #expect(place.day == 20_260_512)
        #expect(place.countryCode == "IT")
        #expect(place.cityId == 3_169_070)
        #expect(place.regionId == "IT-LAZ")
        #expect(place.lastSeen == captured)
        #expect(place.isInferred == false)
    }

    @Test func overrideWins() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        munich(days(from: 20_260_401, to: 20_260_510), context)
        verona(days(from: 20_260_511, to: 20_260_512), context)
        munich([20_260_513], context)
        let visits = try context.fetch(FetchDescriptor<DayVisit>())

        let automatic = Journal.make(visits: visits, homeOverride: nil, today: 20_260_513)
        #expect(automatic.home == "DE-BY")
        #expect(automatic.detectedHome == "DE-BY")
        #expect(automatic.trips.count == 1)

        let overridden = Journal.make(visits: visits, homeOverride: "IT-VEN", today: 20_260_513)
        #expect(overridden.home == "IT-VEN")
        #expect(overridden.detectedHome == "DE-BY")
        // Von Verona aus gesehen sind die Tage in München Reisen: 0401–0510 und der heutige Tag 0513 (läuft noch).
        #expect(overridden.trips.contains { $0.startDay == 20_260_401 && $0.endDay == 20_260_510 })
        #expect(overridden.trips.contains { $0.startDay == 20_260_513 && $0.isOngoing })
        #expect(overridden.trips.count == 2)

        let empty = Journal.make(visits: visits, homeOverride: "", today: 20_260_513)
        #expect(empty.home == "DE-BY")
        #expect(empty.trips == automatic.trips)
    }

    @Test func tripsNewestFirst() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        munich(days(from: 20_260_101, to: 20_260_130), context)
        verona(days(from: 20_260_201, to: 20_260_202), context)
        munich(days(from: 20_260_203, to: 20_260_210), context)
        // 20260211 bis 20260213 ohne Erfassung: drei Tage Lücke zwischen zwei Tagen in München.
        munich(days(from: 20_260_214, to: 20_260_228), context)
        rome(days(from: 20_260_301, to: 20_260_303), context)
        munich(days(from: 20_260_304, to: 20_260_305), context)
        let visits = try context.fetch(FetchDescriptor<DayVisit>())

        let journal = Journal.make(visits: visits, homeOverride: nil, today: 20_260_305)
        guard journal.trips.count >= 2 else {
            Issue.record("Zwei Reisen erwartet, gefunden: \(journal.trips.count)")
            return
        }
        #expect(journal.trips[0].startDay > journal.trips[1].startDay)

        let inferred = Set(journal.days.filter(\.isInferred).map(\.day))
        #expect([20_260_211, 20_260_212, 20_260_213].allSatisfy { inferred.contains($0) },
                "Die drei Tage der Erfassungslücke sind nicht als abgeleitet markiert")
    }

    @Test func homeOverrideSetting() {
        #expect(AppSettings.homeRegionOverride == "homeRegionOverride")

        AppSettings.registerDefaults()
        let value = UserDefaults.standard.string(forKey: AppSettings.homeRegionOverride)
        #expect(value == nil || value == "", "Heimatgebiet ist ohne Einstellung nicht leer: \(value ?? "")")
    }
}
