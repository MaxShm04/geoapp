import Foundation

/// Ein Aufenthalt: aufeinanderfolgende Tage an einem Ort, `first` bis `last` (yyyymmdd, einschließlich).
public struct Stay: Equatable, Hashable, Sendable {
    public let first: Int
    public let last: Int

    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }

    public var dayCount: Int {
        DayKey.daysBetween(first, last) + 1
    }
}

/// Die Aufenthalte eines Jahres, neueste zuerst.
public struct YearStays: Equatable, Sendable {
    public let year: Int
    public let stays: [Stay]

    public init(year: Int, stays: [Stay]) {
        self.year = year
        self.stays = stays
    }

    public var dayCount: Int {
        stays.reduce(0) { $0 + $1.dayCount }
    }
}

/// Die Tage eines Orts für die Ortsansicht: als Liste von Aufenthalten und als Monatsblätter.
/// Arbeitet nur mit Tagen (yyyymmdd), nie mit Positionen.
public enum PlaceCalendar {
    /// Verschiedene Tage, neueste zuerst.
    public static func distinctDays(_ days: [Int]) -> [Int] {
        Set(days).sorted(by: >)
    }

    /// Aufeinanderfolgende Tage bilden einen Aufenthalt. Neueste zuerst.
    public static func stays(days: [Int]) -> [Stay] {
        var result: [Stay] = []
        for day in distinctDays(days) {
            if let current = result.last, DayKey.adding(-1, to: current.first) == day {
                result[result.count - 1] = Stay(first: day, last: current.last)
            } else {
                result.append(Stay(first: day, last: day))
            }
        }
        return result
    }

    /// Aufenthalte je Jahr, neuestes Jahr zuerst. Ein Aufenthalt über den Jahreswechsel wird geteilt.
    public static func staysByYear(days: [Int]) -> [YearStays] {
        Dictionary(grouping: Set(days), by: DayKey.year)
            .sorted { $0.key > $1.key }
            .map { YearStays(year: $0.key, stays: stays(days: $0.value)) }
    }

    /// Monate (yyyymm) mit mindestens einem Tag, neueste zuerst.
    public static func months(days: [Int]) -> [Int] {
        Set(days.map(month(of:))).sorted(by: >)
    }

    /// Zellen eines Monatsblatts in Wochenzeilen: zuerst `nil` bis zum Wochentag des Ersten, dann 1 bis Monatsende.
    /// `firstWeekday` wie `Calendar.firstWeekday` (1 = Sonntag, 2 = Montag).
    public static func monthGrid(month: Int, firstWeekday: Int) -> [Int?] {
        guard let first = utc.date(from: DateComponents(year: month / 100, month: month % 100, day: 1)),
              let length = utc.range(of: .day, in: .month, for: first)?.count else { return [] }
        let weekday = utc.component(.weekday, from: first)
        let leading = (weekday - firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1...length).map(Optional.some)
    }

    /// Monat eines Tages als yyyymm.
    public static func month(of day: Int) -> Int {
        day / 100
    }

    /// Tag im Monat.
    public static func day(_ day: Int) -> Int {
        day % 100
    }

    public static func dayKey(month: Int, day: Int) -> Int {
        month * 100 + day
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
