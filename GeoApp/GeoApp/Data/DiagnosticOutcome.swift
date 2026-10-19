import Foundation

/// Ergebnis einer Erfassung im Diagnose-Log. Gespeichert wird ein fester Code, angezeigt der Text
/// in der Gerätesprache. Ältere Einträge mit deutschem Freitext erscheinen unverändert.
enum DiagnosticOutcome {
    static let newDay = "newDay"
    static let flight = "rejected.flight"
    static let inaccurate = "rejected.inaccurate"
    static let invalidAccuracy = "rejected.invalidAccuracy"
    static let noCountry = "noCountry"
    static let noLocation = "noLocation"

    /// Weitere Erfassung am selben Tag, mit der Zahl der Erfassungen.
    static func sameDay(_ count: Int) -> String { "sameDay:\(count)" }

    static func text(for code: String) -> String {
        switch code {
        case newDay: return String(localized: "new day")
        case flight: return String(localized: "ignored: flight")
        case inaccurate: return String(localized: "ignored: inaccurate")
        case invalidAccuracy: return String(localized: "ignored: invalid accuracy")
        case noCountry: return String(localized: "no country")
        case noLocation: return String(localized: "no location")
        default:
            if code.hasPrefix("sameDay:"), let count = Int(code.dropFirst("sameDay:".count)) {
                return String(localized: "already recorded today (\(count)×)")
            }
            return code
        }
    }
}
