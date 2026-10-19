import Foundation
import Testing
@testable import GeoCore

struct DayKeyTests {
    @Test func yearAndMonth() {
        #expect(DayKey.year(20260519) == 2026)
        #expect(DayKey.month(20260519) == 5)
        #expect(DayKey.month(20261201) == 12)
    }

    @Test func addingAcrossMonthAndYear() {
        #expect(DayKey.adding(1, to: 20260131) == 20260201)
        #expect(DayKey.adding(1, to: 20261231) == 20270101)
        #expect(DayKey.adding(-1, to: 20260301) == 20260228)
        #expect(DayKey.adding(1, to: 20280228) == 20280229)
        #expect(DayKey.adding(0, to: 20260519) == 20260519)
        #expect(DayKey.adding(30, to: 20260101) == 20260131)
    }

    @Test func daysBetween() {
        #expect(DayKey.daysBetween(20260101, 20260101) == 0)
        #expect(DayKey.daysBetween(20260101, 20260201) == 31)
        #expect(DayKey.daysBetween(20261231, 20270101) == 1)
        #expect(DayKey.daysBetween(20260201, 20260101) == -31)
        // Umstellung auf Sommerzeit am 29. März 2026
        #expect(DayKey.daysBetween(20260328, 20260330) == 2)
    }

    @Test func dateRoundTrip() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!

        let date = try #require(DayKey.date(20260519, calendar: calendar))
        #expect(date == calendar.startOfDay(for: date))
        #expect(VisitRules.dayKey(for: date, calendar: calendar) == 20260519)

        let afternoon = date.addingTimeInterval(13 * 3600)
        #expect(DayKey.today(now: afternoon, calendar: calendar) == 20260519)
    }
}
