import Foundation
import Testing
@testable import GeoCore

/// Ortsansicht: Tage eines Orts als Aufenthalte (Liste) und als Monatsblätter (Kalender).
struct PlaceCalendarTests {
    @Test func distinctDaysNewestFirst() {
        #expect(PlaceCalendar.distinctDays([20260103, 20260101, 20260103]) == [20260103, 20260101])
        #expect(PlaceCalendar.distinctDays([]) == [])
    }

    @Test func consecutiveDaysFormOneStay() {
        let stays = PlaceCalendar.stays(days: [20260102, 20260101, 20260103, 20260110, 20260102])
        #expect(stays == [Stay(first: 20260110, last: 20260110), Stay(first: 20260101, last: 20260103)])
        #expect(stays.map(\.dayCount) == [1, 3])
        #expect(PlaceCalendar.stays(days: []) == [])
    }

    @Test func stayAcrossMonthEnd() {
        #expect(PlaceCalendar.stays(days: [20260131, 20260201]) == [Stay(first: 20260131, last: 20260201)])
        #expect(PlaceCalendar.stays(days: [20280228, 20280229, 20280301]).first?.dayCount == 3)
    }

    /// Je Jahr ein Abschnitt, neuestes zuerst. Ein Aufenthalt über Silvester zählt in beiden Jahren.
    @Test func staysGroupedByYear() {
        let years = PlaceCalendar.staysByYear(days: [20251230, 20251231, 20260101, 20240505])
        #expect(years == [
            YearStays(year: 2026, stays: [Stay(first: 20260101, last: 20260101)]),
            YearStays(year: 2025, stays: [Stay(first: 20251230, last: 20251231)]),
            YearStays(year: 2024, stays: [Stay(first: 20240505, last: 20240505)]),
        ])
        #expect(years.map(\.dayCount) == [1, 2, 1])
    }

    @Test func monthsWithVisitsNewestFirst() {
        #expect(PlaceCalendar.months(days: [20260115, 20260120, 20251201]) == [202601, 202512])
        #expect(PlaceCalendar.months(days: []) == [])
    }

    /// 1. Februar 2026 ist ein Sonntag, 1. Mai 2026 ein Freitag.
    @Test func monthGridLeadingBlanks() {
        let mondayFirst = PlaceCalendar.monthGrid(month: 202602, firstWeekday: 2)
        #expect(mondayFirst.prefix(6).allSatisfy { $0 == nil })
        #expect(mondayFirst[6] == 1)
        #expect(mondayFirst.compactMap { $0 } == Array(1...28))
        #expect(mondayFirst.count == 34)

        let sundayFirst = PlaceCalendar.monthGrid(month: 202602, firstWeekday: 1)
        #expect(sundayFirst.first == 1)
        #expect(sundayFirst.count == 28)

        let may = PlaceCalendar.monthGrid(month: 202605, firstWeekday: 2)
        #expect(may.prefix(while: { $0 == nil }).count == 4)
        #expect(may.compactMap { $0 }.last == 31)
    }

    @Test func monthGridLeapYear() {
        #expect(PlaceCalendar.monthGrid(month: 202802, firstWeekday: 2).compactMap { $0 }.last == 29)
        #expect(PlaceCalendar.monthGrid(month: 202702, firstWeekday: 2).compactMap { $0 }.last == 28)
    }

    @Test func monthKeyParts() {
        #expect(PlaceCalendar.month(of: 20260519) == 202605)
        #expect(PlaceCalendar.day(20260519) == 19)
        #expect(PlaceCalendar.dayKey(month: 202605, day: 3) == 20260503)
    }
}
