import Foundation
import Observation
import StoreKit
import WidgetKit

/// Pro-Abo: schaltet die Pro-Funktionen frei. Der Zustand lebt nur im Arbeitsspeicher.
@MainActor @Observable
final class ProStore {
    /// Produkt-IDs aus App Store Connect (D5).
    static let productIDs = ProRules.productIDs

    /// Rechtliche Links für die Paywall (D8).
    enum Links {
        static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        // Platzhalter, bis Max die echte Seite nennt (siehe docs/phases/phase-1.md, D8).
        static let privacy = URL(string: "https://example.com/geoapp/privacy")!
    }

    /// Ein Abo gilt, wenn es zu Pro gehört, nicht widerrufen oder ersetzt ist und nicht abgelaufen ist.
    static func isPro(facts: [EntitlementFact], now: Date) -> Bool {
        ProRules.isPro(facts: facts, now: now)
    }

    /// Gültiges Abo laut StoreKit.
    private(set) var isEntitled = false
    #if DEBUG
    /// Pro-Freischaltung aus dem Beta-Menü, nur in Debug-Builds einkompiliert.
    private(set) var betaProOverride = false
    /// Pro-Funktionen frei: Abo oder Beta-Freischaltung (`ProRules.unlocked`).
    var isPro: Bool { ProRules.unlocked(entitled: isEntitled, betaOverride: betaProOverride) }
    #else
    /// Pro-Funktionen frei: nur mit gültigem Abo.
    var isPro: Bool { isEntitled }
    #endif
    private(set) var products: [Product] = []
    private(set) var productsUnavailable = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    #if DEBUG
    /// Wo die Beta-Freischaltung liegt; `nil` = ohne Freischaltung (etwa in Tests).
    @ObservationIgnored private let betaDefaults: UserDefaults?
    #endif

    /// `betaDefaults` wirkt nur in Debug-Builds; Release ignoriert den Wert.
    init(betaDefaults: UserDefaults? = nil) {
        #if DEBUG
        self.betaDefaults = betaDefaults
        betaProOverride = BetaSettings.proOverride(in: betaDefaults)
        #endif
    }

    func refresh(facts: [EntitlementFact], now: Date = .now) {
        isEntitled = Self.isPro(facts: facts, now: now)
    }

    #if DEBUG
    /// Schaltet Pro lokal frei oder wieder ab und lädt die Widgets neu, die den Wert aus der App Group lesen.
    func setBetaProOverride(_ on: Bool) {
        betaProOverride = on
        BetaSettings.setProOverride(on, in: betaDefaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

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

/// Funktionen, die Pro benötigen. Jede hat einen freien Teil, siehe `ProGate` (Phase 2, D10).
enum ProFeature: String, CaseIterable {
    case yearFilter, timeline, statistics, widgets

    /// Ob ein Feature ohne Pro gesperrt ist. Phase 2 sperrt alle Funktionen, jede mit einem freien Teil (D10).
    static func isGated(_ feature: ProFeature) -> Bool {
        switch feature {
        // Jede Funktion hat einen freien Teil, siehe `ProGate`.
        case .yearFilter, .timeline, .statistics, .widgets:
            return true
        }
    }
}
