import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import GeoApp

/// Testkauf mit der lokalen StoreKit-Konfiguration `GeoApp/Products.storekit` (Fall 25).
/// Läuft gegen die StoreKit-Testumgebung des Simulators, ohne Netz und ohne Konto.
@MainActor
@Suite(.serialized)
struct ProPurchaseTests {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // GeoAppTests
        .deletingLastPathComponent()   // GeoApp
        .appendingPathComponent("Products.storekit")

    @Test func purchaseUnlocksPro() async throws {
        let session = try SKTestSession(contentsOf: Self.configURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let store = ProStore()
        await store.loadProducts()
        #expect(store.products.map(\.id) == ProStore.productIDs)
        let yearly = try #require(store.products.first { $0.id == "de.max.geoapp.pro.yearly" })
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)

        await store.refreshFromStoreKit()
        #expect(store.isPro == false, "Vor dem Kauf")

        #expect(try await store.purchase(yearly) == true)
        #expect(store.isPro == true)

        session.clearTransactions()
    }
}
