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

    /// Ein Abo gilt, wenn es zu Pro gehört, nicht widerrufen oder ersetzt ist und nicht abgelaufen ist.
    static func isPro(facts: [EntitlementFact], now: Date) -> Bool {
        facts.contains { fact in
            productIDs.contains(fact.productID)
                && !fact.revoked
                && !fact.isUpgraded
                && (fact.expires.map { $0 > now } ?? true)
        }
    }

    /// Pro gilt mit gültigem Abo oder, nur in Debug-Builds, mit der Freischaltung aus dem Beta-Menü.
    static func unlocked(entitled: Bool, betaOverride: Bool) -> Bool {
        entitled || (BetaSettings.isAvailable && betaOverride)
    }
}
