import Foundation
import Testing
@testable import GeoCore

struct HomeRegionTests {
    /// Tag `days` Tage nach `day` (yyyymmdd), im gregorianischen Kalender in UTC.
    private func shifted(_ day: Int, by days: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = DateComponents(year: day / 10000, month: day / 100 % 100, day: day % 100)
        let date = calendar.date(from: start)!
        let next = calendar.date(byAdding: .day, value: days, to: date)!
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        return parts.year! * 10000 + parts.month! * 100 + parts.day!
    }

    /// `count` aufeinanderfolgende Tage ab `first`.
    private func days(from first: Int, count: Int) -> [Int] {
        (0..<count).map { shifted(first, by: $0) }
    }

    @Test func mostDaysInWindowWins() {
        let home = days(from: 20260401, count: 50).map { PlaceDay(day: $0, countryCode: "DE", regionId: "DE-BY") }
        let trip = days(from: 20260521, count: 10).map { PlaceDay(day: $0, countryCode: "IT", regionId: "IT-LAZ") }

        #expect(HomeRegion.detect(home + trip, today: 20260531) == "DE-BY")
        #expect(HomeRegion.windowDays == 90)
    }

    @Test func oldDaysOutsideWindowIgnored() {
        let old = days(from: shifted(20250101, by: -199), count: 200).map { PlaceDay(day: $0, countryCode: "DE", regionId: "DE-BY") }
        let recent = days(from: 20260501, count: 10).map { PlaceDay(day: $0, countryCode: "FR", regionId: "FR-IDF") }

        #expect(HomeRegion.detect(old + recent, today: 20260531) == "FR-IDF")
    }

    @Test func countsDistinctDays() {
        let salzburgEntries = [2766824, 2761369, 3164527, 3164603, 3176959].map {
            PlaceDay(day: 20260510, countryCode: "AT", cityId: $0, regionId: "AT-SBG")
        }
        let munichDays = [20260511, 20260512].map {
            PlaceDay(day: $0, countryCode: "DE", cityId: 2867714, regionId: "DE-BY")
        }

        #expect(HomeRegion.detect(salzburgEntries + munichDays, today: 20260531) == "DE-BY")
    }

    @Test func tieGoesToMoreRecent() {
        let austria = days(from: 20260501, count: 5).map { PlaceDay(day: $0, countryCode: "AT", regionId: "AT-SBG") }
        let switzerland = days(from: 20260510, count: 5).map { PlaceDay(day: $0, countryCode: "CH", regionId: "CH-ZH") }

        #expect(HomeRegion.detect(austria + switzerland, today: 20260531) == "CH-ZH")
    }

    @Test func noRegionFallsBackToCountry() {
        #expect(PlaceDay(day: 20260501, countryCode: "MC", regionId: nil).areaKey == "MC")
        #expect(PlaceDay(day: 20260501, countryCode: "DE", regionId: "DE-BY").areaKey == "DE-BY")

        let monaco = days(from: 20260525, count: 5).map { PlaceDay(day: $0, countryCode: "MC", regionId: nil) }
        #expect(HomeRegion.detect(monaco, today: 20260531) == "MC")
    }

    @Test func noRecentDataUsesLatestWindow() {
        let march2024 = days(from: 20240301, count: 10).map { PlaceDay(day: $0, countryCode: "DE", regionId: "DE-BY") }

        #expect(HomeRegion.detect(march2024, today: 20260531) == "DE-BY")
        #expect(HomeRegion.detect([], today: 20260531) == nil)
    }
}
