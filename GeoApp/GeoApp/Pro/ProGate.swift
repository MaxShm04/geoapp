import Foundation
import GeoCore

/// Was ohne Pro geht (Entscheidung D10).
enum ProGate {
    /// Jahr auf der Karte, in den Reisen oder in der Statistik.
    static func allows(_ feature: ProFeature, year: YearFilter, currentYear: Int, isPro: Bool) -> Bool {
        if isPro { return true }
        switch feature {
        case .yearFilter:
            switch year {
            case .all: return true
            case .year(let value): return value == currentYear
            }
        case .timeline, .statistics:
            if case .year(let value) = year { return value == currentYear }
            return false
        case .widgets:
            return false
        }
    }

    /// Statistik im Detail: Tage je Land, Reisetage je Monat, längste Reise.
    static func allowsStatisticsDetail(isPro: Bool) -> Bool {
        isPro
    }

    static func allowsWidget(_ kind: WidgetKind, isPro: Bool) -> Bool {
        isPro || kind == WidgetKind.free
    }
}
