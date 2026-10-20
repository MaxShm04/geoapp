import Foundation

/// Beta-Menü zum Testen auf dem eigenen iPhone: Testschalter ein- und ausblenden, Pro lokal freischalten
/// oder ein Test-Abo so behandeln, als wäre es beendet.
/// Gibt es nur in Debug-Builds. In Release (App Store, TestFlight) sind Schlüssel, Setter und Menü nicht
/// einkompiliert; `proOverride(in:)` liefert dort fest `false`.
nonisolated enum BetaSettings {
    #if DEBUG
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    /// Defaults der App Group, damit die Widgets die Pro-Freischaltung sehen.
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    #if DEBUG
    /// Pro-Freischaltung, in den Defaults der App Group.
    static let proOverrideKey = "betaProOverride"
    /// Abo ignorieren („wie nicht abonniert“), in den Defaults der App Group.
    static let ignoresSubscriptionKey = "betaIgnoresSubscription"
    /// Testschalter in den Einstellungen sichtbar, in `UserDefaults.standard` (nur App).
    static let testControlsKey = "betaTestControls"

    static func setProOverride(_ on: Bool, in defaults: UserDefaults?) {
        defaults?.set(on, forKey: proOverrideKey)
    }

    static func setIgnoresSubscription(_ on: Bool, in defaults: UserDefaults?) {
        defaults?.set(on, forKey: ignoresSubscriptionKey)
    }
    #endif

    /// Ob Pro lokal freigeschaltet ist. In Release immer `false`.
    static func proOverride(in defaults: UserDefaults?) -> Bool {
        #if DEBUG
        return defaults?.bool(forKey: proOverrideKey) ?? false
        #else
        return false
        #endif
    }

    /// Ob ein gültiges Abo ignoriert wird, als wäre es beendet. In Release immer `false`.
    static func ignoresSubscription(in defaults: UserDefaults?) -> Bool {
        #if DEBUG
        return defaults?.bool(forKey: ignoresSubscriptionKey) ?? false
        #else
        return false
        #endif
    }

    /// Ob die Testschalter in den Einstellungen erscheinen. In Debug folgt das dem Beta-Schalter;
    /// in Release bleiben Diagnose-Log und Ortsprüfung wie bisher sichtbar, die Testdaten sind dort nicht einkompiliert.
    static func showsTestControls(switchOn: Bool) -> Bool {
        #if DEBUG
        return switchOn
        #else
        return true
        #endif
    }
}
