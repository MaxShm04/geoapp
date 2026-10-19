import Foundation
import Testing
@testable import GeoApp

private let monthlyID = "de.max.geoapp.pro.monthly"
private let yearlyID = "de.max.geoapp.pro.yearly"
private let proTestNow = Date(timeIntervalSince1970: 1_800_000_000)
private let proTestDay: TimeInterval = 86_400

private func fact(_ productID: String, revoked: Bool = false, expires: Date?, upgraded: Bool = false) -> EntitlementFact {
    EntitlementFact(productID: productID, revoked: revoked, expires: expires, isUpgraded: upgraded)
}

/// Pro-Abo: Freischaltung aus den Berechtigungen, Produktliste, StoreKit-Konfiguration und Datenschutz.
@MainActor
struct ProStoreTests {
    @Test func noEntitlementsMeansFree() {
        #expect(ProStore.isPro(facts: [], now: proTestNow) == false)
    }

    @Test func activeYearly() {
        let facts = [fact(yearlyID, expires: proTestNow.addingTimeInterval(30 * proTestDay))]
        #expect(ProStore.isPro(facts: facts, now: proTestNow) == true)
    }

    @Test func expired() {
        let facts = [fact(monthlyID, expires: proTestNow.addingTimeInterval(-1))]
        #expect(ProStore.isPro(facts: facts, now: proTestNow) == false)
    }

    @Test func revoked() {
        let facts = [fact(yearlyID, revoked: true, expires: proTestNow.addingTimeInterval(30 * proTestDay))]
        #expect(ProStore.isPro(facts: facts, now: proTestNow) == false)
    }

    /// Ein altes Monatsabo, das durch ein Upgrade ersetzt wurde, gibt allein keinen Zugang; das Jahresabo schon.
    @Test func upgradedIgnored() {
        let upgraded = fact(monthlyID, expires: proTestNow.addingTimeInterval(10 * proTestDay), upgraded: true)
        #expect(ProStore.isPro(facts: [upgraded], now: proTestNow) == false)

        let yearly = fact(yearlyID, expires: proTestNow.addingTimeInterval(300 * proTestDay))
        #expect(ProStore.isPro(facts: [upgraded, yearly], now: proTestNow) == true)
    }

    @Test func unknownProduct() {
        let facts = [fact("com.other.product", expires: proTestNow.addingTimeInterval(30 * proTestDay))]
        #expect(ProStore.isPro(facts: facts, now: proTestNow) == false)
    }

    @Test func productIDs() {
        #expect(ProStore.productIDs == ["de.max.geoapp.pro.monthly", "de.max.geoapp.pro.yearly"])
    }

    /// Prüft `GeoApp/Products.storekit` und das Schema `GeoApp.xcscheme`, beide neben dem Xcode-Projekt.
    @Test func storekitConfigMatches() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GeoAppTests
            .deletingLastPathComponent()   // GeoApp

        let configURL = root.appendingPathComponent("Products.storekit")
        guard let data = try? Data(contentsOf: configURL),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Products.storekit fehlt oder ist kein gültiges JSON: \(configURL.path)")
            return
        }

        let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []
        #expect(groups.count == 1, "Genau eine Abo-Gruppe erwartet")
        let subscriptions = groups.first?["subscriptions"] as? [[String: Any]] ?? []
        let ids = subscriptions.compactMap { $0["productID"] as? String }
        #expect(ids.contains(monthlyID), "Monatsabo fehlt")
        #expect(ids.contains(yearlyID), "Jahresabo fehlt")

        for subscription in subscriptions {
            let shareable = (subscription["familyShareable"] as? Bool) == true
            #expect(shareable, "Familienfreigabe fehlt bei \(subscription["productID"] ?? "?")")
        }

        let yearly = subscriptions.first { ($0["productID"] as? String) == yearlyID }
        let offer = yearly?["introductoryOffer"] as? [String: Any]
        #expect((offer?["paymentMode"] as? String) == "free", "Jahresabo ohne kostenlose Probezeit")
        let period = offer?["subscriptionPeriod"] as? String
        #expect(period == "P1W" || period == "P7D", "Probezeit ist nicht 7 Tage")

        let schemeURL = root.appendingPathComponent("GeoApp.xcodeproj/xcshareddata/xcschemes/GeoApp.xcscheme")
        guard let scheme = try? String(contentsOf: schemeURL, encoding: .utf8) else {
            Issue.record("GeoApp.xcscheme fehlt: \(schemeURL.path)")
            return
        }
        let identifier = scheme.firstMatch(of: /StoreKitConfigurationFileReference\s+identifier\s*=\s*"([^"]*)"/)?.1
        #expect(identifier?.hasSuffix("Products.storekit") == true, "Schema verweist nicht auf Products.storekit")
    }

    /// Phase 2 (D10) sperrt Jahresfilter, Zeitleiste, Statistik und Widgets; ersetzt Phase 1, Fall 22.
    @Test func gatesOnInPhase2() {
        #expect(ProFeature.allCases == [.yearFilter, .timeline, .statistics, .widgets])
        for feature in ProFeature.allCases {
            #expect(ProFeature.isGated(feature) == true, "\(feature.rawValue) ist nicht gesperrt")
        }
    }

    /// Der Pro-Zustand landet weder in UserDefaults noch im Speicher; nur die Schema-Entitäten zählen.
    @Test func storesNothing() {
        let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let store = ProStore()
        store.refresh(facts: [fact(yearlyID, expires: proTestNow.addingTimeInterval(30 * proTestDay))], now: proTestNow)
        let added = Set(UserDefaults.standard.dictionaryRepresentation().keys).subtracting(before)
        let proKeys = added.filter { key in
            let lowered = key.lowercased()
            return lowered.contains("pro") || lowered.contains("entitlement")
        }
        #expect(proKeys.isEmpty, "Neue UserDefaults-Schlüssel mit Pro-Bezug: \(proKeys.sorted())")
        #expect(store.isPro == true)

        let entities = Store.schema.entities.map(\.name)
        let proEntities = entities.filter { name in
            let lowered = name.lowercased()
            return lowered.contains("pro") || lowered.contains("entitlement")
        }
        #expect(proEntities.isEmpty, "Pro-Entität im Schema: \(proEntities)")
    }
}
