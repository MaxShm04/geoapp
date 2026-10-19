import Foundation
import Observation
import StoreKit

/// Ein Berechtigungsnachweis aus StoreKit, ohne StoreKit-Typen, damit die Regeln testbar bleiben.
struct EntitlementFact: Sendable {
    let productID: String
    let revoked: Bool
    let expires: Date?
    let isUpgraded: Bool
}

/// Pro-Abo: schaltet die Pro-Funktionen frei. Der Zustand lebt nur im Arbeitsspeicher.
@MainActor @Observable
final class ProStore {
    /// Produkt-IDs aus App Store Connect (D5).
    static let productIDs = ["de.max.geoapp.pro.monthly", "de.max.geoapp.pro.yearly"]

    /// Rechtliche Links für die Paywall (D8).
    enum Links {
        static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        // Platzhalter, bis Max die echte Seite nennt (siehe docs/phases/phase-1.md, D8).
        static let privacy = URL(string: "https://example.com/geoapp/privacy")!
    }

    /// Ein Abo gilt, wenn es zu Pro gehört, nicht widerrufen oder ersetzt ist und nicht abgelaufen ist.
    static func isPro(facts: [EntitlementFact], now: Date) -> Bool {
        facts.contains { fact in
            guard productIDs.contains(fact.productID), !fact.revoked, !fact.isUpgraded else { return false }
            guard let expires = fact.expires else { return true }
            return expires > now
        }
    }

    private(set) var isPro = false
    private(set) var products: [Product] = []
    private(set) var productsUnavailable = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {}

    func refresh(facts: [EntitlementFact], now: Date = .now) {
        isPro = Self.isPro(facts: facts, now: now)
    }

    /// Lädt die Produkte, Monatsabo zuerst.
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
            productsUnavailable = products.isEmpty
        } catch {
            productsUnavailable = true
        }
    }

    /// Liest alle gültigen Berechtigungen von StoreKit und setzt den Pro-Zustand.
    func refreshFromStoreKit() async {
        var facts: [EntitlementFact] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            facts.append(EntitlementFact(
                productID: transaction.productID,
                revoked: transaction.revocationDate != nil,
                expires: transaction.expirationDate,
                isUpgraded: transaction.isUpgraded
            ))
        }
        refresh(facts: facts)
    }

    /// Startet den Transaktions-Listener und die erste Prüfung. Wirkt nur einmal.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.refreshFromStoreKit()
            }
        }
        Task { await refreshFromStoreKit() }
        Task { await loadProducts() }
    }

    /// Kauft ein Produkt. Liefert `true`, wenn der Kauf bestätigt wurde.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refreshFromStoreKit()
            return true
        case .success(.unverified), .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Stellt Käufe wieder her, etwa auf einem neuen Gerät.
    func restore() async {
        try? await AppStore.sync()
        await refreshFromStoreKit()
    }
}

/// Funktionen, die Pro benötigen. In Phase 1 ist keine davon gesperrt.
enum ProFeature: String, CaseIterable {
    case yearFilter, statistics, widgets

    /// Ob ein Feature ohne Pro gesperrt ist. Phase 1 sperrt nichts (D7).
    static func isGated(_ feature: ProFeature) -> Bool {
        switch feature {
        // Phase 2 hängt hier die Sperren an (Jahresfilter, Statistik, Widgets).
        case .yearFilter, .statistics, .widgets:
            return false
        }
    }
}
