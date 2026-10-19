import Foundation
import Testing
@testable import GeoCore

struct YearFilterTests {
    @Test func contains() {
        #expect(YearFilter.all.contains(day: 20190101) == true)
        #expect(YearFilter.year(2026).contains(day: 20260519) == true)
        #expect(YearFilter.year(2026).contains(day: 20251231) == false)
    }

    @Test func availableYears() {
        #expect(YearFilter.availableYears(days: [20240105, 20260519, 20240210, 20250101], currentYear: 2026) == [2026, 2025, 2024])
        #expect(YearFilter.availableYears(days: [], currentYear: 2026) == [2026])
        #expect(YearFilter.availableYears(days: [20240105], currentYear: 2026) == [2026, 2024])
    }

    @Test func storageRoundTrip() {
        #expect(YearFilter.all.storageValue == "all")
        #expect(YearFilter.year(2025).storageValue == "2025")
        #expect(YearFilter(storageValue: "all") == .all)
        #expect(YearFilter(storageValue: "2025") == .year(2025))
        #expect(YearFilter(storageValue: "garbage") == nil)
        #expect(YearFilter(storageValue: "") == nil)
    }
}
