import Foundation

/// Welche Jahre die Karte, die Reisen oder die Statistik zeigen.
public enum YearFilter: Hashable, Sendable {
    case all
    case year(Int)

    public func contains(day: Int) -> Bool {
        switch self {
        case .all: true
        case .year(let year): DayKey.year(day) == year
        }
    }

    /// Jahre mit Daten, absteigend. Das laufende Jahr ist immer dabei.
    public static func availableYears(days: [Int], currentYear: Int) -> [Int] {
        Set(days.map(DayKey.year)).union([currentYear]).sorted(by: >)
    }

    /// Wert für `@AppStorage`: `"all"` oder die Jahreszahl.
    public var storageValue: String {
        switch self {
        case .all: "all"
        case .year(let year): String(year)
        }
    }

    public init?(storageValue: String) {
        if storageValue == "all" {
            self = .all
        } else if let year = Int(storageValue), year > 0 {
            self = .year(year)
        } else {
            return nil
        }
    }
}
