import Foundation
import Testing
@testable import GeoApp

private let refreshNow = Date(timeIntervalSince1970: 1_800_000_000)

private func monthly(expires: Date?) -> EntitlementFact {
    EntitlementFact(productID: "de.max.geoapp.pro.monthly", revoked: false, expires: expires, isUpgraded: false)
}

/// Liefert Berechtigungen nach Drehbuch: die erste Abfrage wartet, bis der Test sie freigibt.
private actor ScriptedEntitlements {
    private var first: CheckedContinuation<[EntitlementFact], Never>?
    private var calls = 0
    private let later: [EntitlementFact]

    init(later: [EntitlementFact]) {
        self.later = later
    }

    func next() async -> [EntitlementFact] {
        calls += 1
        guard calls == 1 else { return later }
        return await withCheckedContinuation { first = $0 }
    }

    var firstIsWaiting: Bool { first != nil }

    func releaseFirst(with facts: [EntitlementFact]) {
        first?.resume(returning: facts)
        first = nil
    }
}

/// Fehler „trotz Abo wieder rausgeworfen“ (Oct 20): StoreKit zeigt ein gültiges Monatsabo, die App sagt Free.
@MainActor
struct ProRefreshTests {
    /// Ursache 1: Was StoreKit in `currentEntitlements` liefert, gilt, auch wenn das Ablaufdatum schon vorbei ist
    /// (Kulanzfrist nach einer fehlgeschlagenen Verlängerung, oder die Uhr des Geräts geht anders als die der
    /// StoreKit-Testumgebung). Die App darf das Abo nicht mit der eigenen Uhr verwerfen.
    @Test func entitlementPastExpiryStillCounts() {
        let inGracePeriod = monthly(expires: refreshNow.addingTimeInterval(-3_600))
        #expect(ProRules.isPro(facts: [inGracePeriod]) == true)
        #expect(ProStore.isPro(facts: [inGracePeriod]) == true)

        let store = ProStore(entitlements: { [inGracePeriod] })
        store.refresh(facts: [inGracePeriod])
        #expect(store.isEntitled == true)
        #expect(store.isPro == true)
    }

    /// Ursache 2: Ein einmal falscher Zustand muss sich bei der nächsten Abfrage berichtigen
    /// (Vordergrund, Paywall, Einstellungen), nicht erst beim nächsten Kauf.
    @Test func laterRefreshPicksUpEntitlement() async {
        let script = ScriptedEntitlements(later: [monthly(expires: refreshNow.addingTimeInterval(86_400))])
        let store = ProStore(entitlements: { await script.next() })

        let first = Task { await store.refreshFromStoreKit() }
        while !(await script.firstIsWaiting) { await Task.yield() }
        await script.releaseFirst(with: [])
        await first.value
        #expect(store.isPro == false)

        await store.refreshFromStoreKit()
        #expect(store.isPro == true)
    }

    /// Ursache 3: Eine ältere, langsamere Abfrage darf das Ergebnis einer neueren nicht überschreiben.
    @Test func olderRefreshCannotOverwriteNewer() async {
        let script = ScriptedEntitlements(later: [monthly(expires: refreshNow.addingTimeInterval(86_400))])
        let store = ProStore(entitlements: { await script.next() })

        let slow = Task { await store.refreshFromStoreKit() }
        while !(await script.firstIsWaiting) { await Task.yield() }

        await store.refreshFromStoreKit()
        #expect(store.isPro == true)

        await script.releaseFirst(with: [])
        await slow.value
        #expect(store.isPro == true, "Das veraltete leere Ergebnis hat den Pro-Zustand überschrieben")
    }

    /// Widerrufen, ersetzt oder fremd bleibt ausgeschlossen.
    @Test func revokedUpgradedAndForeignStillExcluded() {
        let future = refreshNow.addingTimeInterval(86_400)
        #expect(!ProRules.isPro(facts: [EntitlementFact(productID: "de.max.geoapp.pro.monthly", revoked: true,
                                                        expires: future, isUpgraded: false)]))
        #expect(!ProRules.isPro(facts: [EntitlementFact(productID: "de.max.geoapp.pro.monthly", revoked: false,
                                                        expires: future, isUpgraded: true)]))
        #expect(!ProRules.isPro(facts: [EntitlementFact(productID: "com.other", revoked: false,
                                                        expires: future, isUpgraded: false)]))
    }
}
