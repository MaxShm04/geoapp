import Foundation

/// Woher eine Erfassung kommt.
public enum CaptureSource: String, Codable, Sendable, CaseIterable {
    /// Significant Location Change, das System weckt die App bei größeren Ortswechseln.
    case significantChange
    /// CLVisit, iOS meldet einen Aufenthalt.
    case visit
    /// Einmalige Abfrage beim Öffnen der App.
    case manual
    /// Testdaten aus den Einstellungen. Lassen sich gezielt wieder entfernen.
    case demo
}

/// Warum eine Position verworfen wurde.
public enum RejectReason: String, Sendable {
    case invalidAccuracy
    case inaccurate
    case flight
}

/// Regeln für den Start laut Briefing. Alle Zahlen sind Startwerte zum Anpassen nach dem Alltagstest.
public enum VisitRules {
    /// Regel 1: Positionen mit horizontaler Genauigkeit über diesem Wert (in Metern) werden ignoriert.
    public static let maxHorizontalAccuracy: Double = 10_000
    /// Regel 3: Schneller als das (in m/s, ~540 km/h) gilt als Flug.
    public static let maxSpeed: Double = 150
    /// Regeln 1 und 3. `speed` ist negativ, wenn unbekannt (wie bei `CLLocation` und Visits).
    public static func rejectReason(horizontalAccuracy: Double, speed: Double) -> RejectReason? {
        if horizontalAccuracy < 0 || !horizontalAccuracy.isFinite { return .invalidAccuracy }
        if horizontalAccuracy > maxHorizontalAccuracy { return .inaccurate }
        if speed > maxSpeed { return .flight }
        return nil
    }

    /// Regel 4: Pro Ort und Tag gibt es einen Eintrag. Der Tag als yyyymmdd in der Zeitzone zum
    /// Zeitpunkt der Erfassung, damit er nach einer Reise über Zeitzonen gleich bleibt.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}
