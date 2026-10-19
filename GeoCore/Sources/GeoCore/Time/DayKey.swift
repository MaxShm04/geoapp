import Foundation

/// Rechnen mit Tagen im Format yyyymmdd (`VisitRules.dayKey`). Ein Tag ist ein Kalenderdatum
/// ohne Zeitzone, deshalb rechnet `DayKey` intern im gregorianischen Kalender in UTC.
public enum DayKey {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func year(_ day: Int) -> Int {
        day / 10_000
    }

    public static func month(_ day: Int) -> Int {
        day / 100 % 100
    }

    /// Der Tag `days` Tage nach `day` (negativ: davor).
    public static func adding(_ days: Int, to day: Int) -> Int {
        guard let date = utcDate(day), let result = utc.date(byAdding: .day, value: days, to: date) else { return day }
        return VisitRules.dayKey(for: result, calendar: utc)
    }

    /// Kalendertage von `from` bis `to`, negativ wenn `to` davor liegt.
    public static func daysBetween(_ from: Int, _ to: Int) -> Int {
        guard let start = utcDate(from), let end = utcDate(to) else { return 0 }
        return utc.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Beginn des Tages in `calendar`.
    public static func date(_ day: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year(day), month: month(day), day: day % 100))
    }

    /// Der heutige Tag in `calendar`.
    public static func today(now: Date = .now, calendar: Calendar = .current) -> Int {
        VisitRules.dayKey(for: now, calendar: calendar)
    }

    private static func utcDate(_ day: Int) -> Date? {
        date(day, calendar: utc)
    }
}
