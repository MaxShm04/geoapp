import Foundation

/// Ein Berechtigungsnachweis aus StoreKit, ohne StoreKit-Typen, damit die Regeln testbar bleiben.
nonisolated struct EntitlementFact: Sendable {
    let productID: String
    let revoked: Bool
    let expires: Date?
    let isUpgraded: Bool
}

/// Regeln für das Pro-Abo, gemeinsam für App und Widgets (Entscheidung D9).
nonisolated enum ProRules {
    /// Produkt-IDs aus App Store Connect (Phase 1, D5).
    static let productIDs = ["de.max.geoapp.pro.monthly", "de.max.geoapp.pro.yearly"]

    /// Ein Abo gilt, wenn es zu Pro gehört und nicht widerrufen oder ersetzt ist.
    ///
    /// Die Fakten kommen aus `Transaction.currentEntitlements`. StoreKit liefert dort nur Abos, die gerade gelten,
    /// auch in der Kulanzfrist nach einer fehlgeschlagenen Verlängerung, wenn das Ablaufdatum schon vorbei ist.
    /// Deshalb kein Vergleich mit der Uhr des Geräts: Der hat gültige Abos verworfen (Fehler vom 20. Oktober 2026).
    static func isPro(facts: [EntitlementFact]) -> Bool {
        facts.contains { fact in
            productIDs.contains(fact.productID) && !fact.revoked && !fact.isUpgraded
        }
    }

    /// Pro gilt mit gültigem Abo. Nur in Debug-Builds wirkt das Beta-Menü: die Freischaltung gibt immer Pro,
    /// „wie nicht abonniert“ lässt ein gültiges Abo außer Acht.
    static func unlocked(entitled: Bool, betaOverride: Bool, ignoresSubscription: Bool = false) -> Bool {
        guard BetaSettings.isAvailable else { return entitled }
        return betaOverride || (entitled && !ignoresSubscription)
    }
}
