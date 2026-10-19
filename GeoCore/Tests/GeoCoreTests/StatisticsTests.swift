import Foundation
import Testing
@testable import GeoCore

struct StatisticsTests {
    /// Ein Ort für jeden Kalendertag ab `start` (yyyymmdd), `count` Tage lang (UTC, gregorianisch).
    private func run(from start: Int, count: Int, countryCode: String, cityId: Int? = nil) -> [PlaceDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: start / 10000, month: start / 100 % 100, day: start % 100))!
        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: first)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let day = parts.year! * 10000 + parts.month! * 100 + parts.day!
            return PlaceDay(day: day, countryCode: countryCode, cityId: cityId)
        }
    }

    @Test func daysPerCountry() {
        var days = run(from: 20260101, count: 10, countryCode: "DE", cityId: 2950159)  // Berlin
        days += run(from: 20260201, count: 4, countryCode: "IT", cityId: 3169070)      // Rome
        days.append(PlaceDay(day: 20260301, countryCode: "DE", cityId: 2867714))       // Munich
        days.append(PlaceDay(day: 20260301, countryCode: "AT", cityId: 2766824))       // Salzburg

        let stats = Statistics.make(year: 2026, days: days, trips: [])
        #expect(stats.daysPerCountry == [
            CountryDays(code: "DE", days: 11),
            CountryDays(code: "IT", days: 4),
            CountryDays(code: "AT", days: 1),
        ])

        // Gleichstand: gleiche Tageszahl, dann Code aufsteigend
        let tie = [
            PlaceDay(day: 20260501, countryCode: "NL"),
            PlaceDay(day: 20260502, countryCode: "BE"),
        ]
        #expect(Statistics.make(year: 2026, days: tie, trips: []).daysPerCountry == [
            CountryDays(code: "BE", days: 1),
            CountryDays(code: "NL", days: 1),
        ])
    }

    @Test func countsPerYear() {
        let days = [
            PlaceDay(day: 20251201, countryCode: "FR", cityId: 2988507),  // Paris
            PlaceDay(day: 20260105, countryCode: "DE", cityId: 2950159),  // Berlin
            PlaceDay(day: 20260210, countryCode: "IT", cityId: 3169070),  // Rome
            PlaceDay(day: 20260211, countryCode: "IT", cityId: 3169070),  // Rome
            PlaceDay(day: 20260301, countryCode: "MC"),                   // nur Land
        ]

        let y2026 = Statistics.make(year: 2026, days: days, trips: [])
        #expect(y2026.countryCodes == ["DE", "IT", "MC"])
        #expect(y2026.cityIds == [2950159, 3169070])

        #expect(Statistics.make(year: 2025, days: days, trips: []).countryCodes == ["FR"])

        let all = Statistics.make(year: nil, days: days, trips: [])
        #expect(all.countryCodes.count == 4)
        #expect(all.cityIds.count == 3)
    }

    @Test func newPlacesThisYear() {
        let days = [
            PlaceDay(day: 20251231, countryCode: "FR", cityId: 2988507),                       // Paris, erfasst
            PlaceDay(day: 20260101, countryCode: "FR", cityId: 2988507, isInferred: true),     // Paris, ergänzt
            PlaceDay(day: 20260105, countryCode: "FR", cityId: 2988507),                       // Paris, erfasst
            PlaceDay(day: 20260210, countryCode: "IT", cityId: 3169070),                       // Rome, erfasst
        ]

        let y2026 = Statistics.make(year: 2026, days: days, trips: [])
        #expect(y2026.newCountryCodes == ["IT"])
        #expect(y2026.newCityIds == [3169070])

        let y2025 = Statistics.make(year: 2025, days: days, trips: [])
        #expect(y2025.newCountryCodes == ["FR"])
        #expect(y2025.newCityIds == [2988507])
    }

    @Test func travelDaysPerMonth() {
        let trips = [
            Trip(startDay: 20260512, endDay: 20260519, dayCount: 8, countryCodes: ["IT"], mainCountryCode: "IT",
                 cityIds: [3169070], isOngoing: false),
            Trip(startDay: 20260629, endDay: 20260702, dayCount: 4, countryCodes: ["AT"], mainCountryCode: "AT",
                 cityIds: [2761369], isOngoing: false),
            Trip(startDay: 20251230, endDay: 20260102, dayCount: 4, countryCodes: ["FR"], mainCountryCode: "FR",
                 cityIds: [2988507], isOngoing: false),
        ]

        let y2026 = Statistics.make(year: 2026, days: [], trips: trips)
        #expect(y2026.travelDaysPerMonth == [2, 0, 0, 0, 8, 2, 2, 0, 0, 0, 0, 0])
        #expect(y2026.travelDays == 14)

        #expect(Statistics.make(year: 2025, days: [], trips: trips).travelDaysPerMonth[11] == 2)
    }

    @Test func longestTrip() {
        let trips = [
            Trip(startDay: 20260512, endDay: 20260519, dayCount: 8, countryCodes: ["IT"], mainCountryCode: "IT",
                 cityIds: [3169070], isOngoing: false),
            Trip(startDay: 20260801, endDay: 20260810, dayCount: 10, countryCodes: ["AT"], mainCountryCode: "AT",
                 cityIds: [2761369], isOngoing: false),
            Trip(startDay: 20261001, endDay: 20261010, dayCount: 10, countryCodes: ["CH"], mainCountryCode: "CH",
                 cityIds: [2657896], isOngoing: false),
            Trip(startDay: 20251220, endDay: 20260105, dayCount: 17, countryCodes: ["FR"], mainCountryCode: "FR",
                 cityIds: [2988507], isOngoing: false),
        ]

        #expect(Statistics.make(year: 2026, days: [], trips: trips).longestTrip?.startDay == 20260801)
        #expect(Statistics.make(year: nil, days: [], trips: trips).longestTrip?.startDay == 20251220)
        #expect(Statistics.make(year: 2026, days: [], trips: []).longestTrip == nil)
    }

    @Test func emptyData() {
        let empty = Statistics.make(year: 2026, days: [], trips: [])
        #expect(empty.countryCodes.isEmpty)
        #expect(empty.cityIds.isEmpty)
        #expect(empty.daysPerCountry.isEmpty)
        #expect(empty.newCountryCodes.isEmpty)
        #expect(empty.newCityIds.isEmpty)
        #expect(empty.travelDaysPerMonth == Array(repeating: 0, count: 12))
        #expect(empty.travelDays == 0)
        #expect(empty.longestTrip == nil)
        #expect(empty.trackedDays == 0)

        let days = [
            PlaceDay(day: 20260105, countryCode: "DE", cityId: 2950159),
            PlaceDay(day: 20260106, countryCode: "DE", cityId: 2950159, isInferred: true),
            PlaceDay(day: 20260107, countryCode: "IT", cityId: 3169070),
        ]
        #expect(Statistics.make(year: 2026, days: days, trips: []).trackedDays == 3)
    }
}
