import Foundation
import GeoCore
import Testing
@testable import GeoApp

private let gateMonthlyID = "de.max.geoapp.pro.monthly"
private let gateYearlyID = "de.max.geoapp.pro.yearly"
private let gateNow = Date(timeIntervalSince1970: 1_800_000_000)
private let gateDay: TimeInterval = 86_400

private func gateFact(_ productID: String, revoked: Bool = false, expires: Date?, upgraded: Bool = false) -> EntitlementFact {
    EntitlementFact(productID: productID, revoked: revoked, expires: expires, isUpgraded: upgraded)
}

/// Freie und Pro-Teile der Funktionen (Phase 2, D9 und D10) und die gemeinsamen Pro-Regeln.
struct ProGateTests {
    @Test func yearFilter() {
        #expect(ProGate.allows(.yearFilter, year: .all, currentYear: 2026, isPro: false) == true)
        #expect(ProGate.allows(.yearFilter, year: .year(2026), currentYear: 2026, isPro: false) == true)
        #expect(ProGate.allows(.yearFilter, year: .year(2025), currentYear: 2026, isPro: false) == false)
        #expect(ProGate.allows(.yearFilter, year: .year(2027), currentYear: 2026, isPro: false) == false)

        #expect(ProGate.allows(.yearFilter, year: .all, currentYear: 2026, isPro: true) == true)
        #expect(ProGate.allows(.yearFilter, year: .year(2026), currentYear: 2026, isPro: true) == true)
        #expect(ProGate.allows(.yearFilter, year: .year(2025), currentYear: 2026, isPro: true) == true)
        #expect(ProGate.allows(.yearFilter, year: .year(2027), currentYear: 2026, isPro: true) == true)
    }

    @Test func timelineAndStatisticsYears() {
        for feature in [ProFeature.timeline, .statistics] {
            #expect(ProGate.allows(feature, year: .year(2026), currentYear: 2026, isPro: false) == true,
                    "\(feature.rawValue): aktuelles Jahr ist frei")
            #expect(ProGate.allows(feature, year: .year(2025), currentYear: 2026, isPro: false) == false,
                    "\(feature.rawValue): altes Jahr ist ohne Pro gesperrt")
            #expect(ProGate.allows(feature, year: .all, currentYear: 2026, isPro: false) == false,
                    "\(feature.rawValue): alle Jahre sind ohne Pro gesperrt")
            #expect(ProGate.allows(feature, year: .all, currentYear: 2026, isPro: true) == true,
                    "\(feature.rawValue): alle Jahre mit Pro")
        }
    }

    @Test func statisticsDetail() {
        #expect(ProGate.allowsStatisticsDetail(isPro: false) == false)
        #expect(ProGate.allowsStatisticsDetail(isPro: true) == true)
    }

    @Test func widgets() {
        #expect(WidgetKind.allCases == [.counter, .newPlaces, .map])
        #expect(WidgetKind.free == .counter)

        #expect(ProGate.allowsWidget(.counter, isPro: false) == true)
        #expect(ProGate.allowsWidget(.newPlaces, isPro: false) == false)
        #expect(ProGate.allowsWidget(.map, isPro: false) == false)

        for kind in WidgetKind.allCases {
            #expect(ProGate.allowsWidget(kind, isPro: true) == true)
        }

        #expect(WidgetKind.counter.kind == "Counter")
        #expect(WidgetKind.newPlaces.kind == "NewPlaces")
        #expect(WidgetKind.map.kind == "Map")
    }

    /// Die Paywall nennt nur Funktionen, die es gibt. Das Wort „upcoming“ bleibt draußen.
    @Test func paywallCopyMatchesShippedFeatures() {
        #expect(PaywallView.featureKeys == [
            "Every year on the map and in your trips",
            "Detailed statistics for every year",
            "All widgets for your Home Screen",
        ])

        // `GeoApp/GeoApp` ist der Quellordner der App, abgeleitet aus diesem Dateipfad.
        let appSourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GeoAppTests
            .deletingLastPathComponent()   // GeoApp
            .appendingPathComponent("GeoApp")

        for path in ["Localizable.xcstrings", "Pro/PaywallView.swift"] {
            let url = appSourceDirectory.appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("\(path) nicht lesbar: \(url.path)")
                continue
            }
            #expect(text.lowercased().contains("upcoming") == false, "\(path) enthält „upcoming“")
        }
    }

    /// Die gemeinsamen Regeln geben dieselben Ergebnisse wie Phase 1 (Fälle 14–19), auch über `ProStore`.
    @MainActor @Test func proRulesShared() {
        let active = [gateFact(gateYearlyID, expires: gateNow.addingTimeInterval(30 * gateDay))]
        let revoked = [gateFact(gateYearlyID, revoked: true, expires: gateNow.addingTimeInterval(30 * gateDay))]
        let upgraded = [gateFact(gateMonthlyID, expires: gateNow.addingTimeInterval(10 * gateDay), upgraded: true)]
        let other = [gateFact("com.other.product", expires: gateNow.addingTimeInterval(30 * gateDay))]

        let cases: [([EntitlementFact], Bool)] = [
            ([], false),
            (active, true),
            (revoked, false),
            (upgraded, false),
            (other, false),
        ]
        for (facts, expected) in cases {
            #expect(ProRules.isPro(facts: facts, now: gateNow) == expected)
            #expect(ProStore.isPro(facts: facts, now: gateNow) == expected)
        }
    }
}
