import Foundation
import GeoCore
import Testing
@testable import GeoApp

private let betaNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Eigene Defaults je Test, damit nichts aus dem Simulator (App Group) hineinwirkt.
private func freshDefaults() -> (UserDefaults, String) {
    let name = "BetaSettingsTests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

/// Beta-Menü: Pro-Freischaltung und Testschalter, nur in Debug-Builds.
@MainActor
struct BetaSettingsTests {
    @Test func availableOnlyInDebug() {
        #if DEBUG
        #expect(BetaSettings.isAvailable == true)
        #else
        #expect(BetaSettings.isAvailable == false)
        #endif
    }

    @Test func unlockedRule() {
        #expect(ProRules.unlocked(entitled: true, betaOverride: false) == true)
        #expect(ProRules.unlocked(entitled: true, betaOverride: true) == true)
        #expect(ProRules.unlocked(entitled: false, betaOverride: false) == false)
        #if DEBUG
        #expect(ProRules.unlocked(entitled: false, betaOverride: true) == true)
        #else
        #expect(ProRules.unlocked(entitled: false, betaOverride: true) == false)
        #endif
    }

    #if DEBUG
    @Test func overrideStoredInDefaults() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(BetaSettings.proOverride(in: defaults) == false)
        #expect(BetaSettings.proOverride(in: nil) == false)
        BetaSettings.setProOverride(true, in: defaults)
        #expect(BetaSettings.proOverride(in: defaults) == true)
        BetaSettings.setProOverride(false, in: defaults)
        #expect(BetaSettings.proOverride(in: defaults) == false)
    }

    /// Die Freischaltung öffnet alle Pro-Teile und gilt auch für einen zweiten Leser derselben Defaults (wie die Widgets).
    @Test func overrideUnlocksGates() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ProStore(betaDefaults: defaults)
        store.refresh(facts: [], now: betaNow)
        #expect(store.isPro == false)
        #expect(ProGate.allows(.yearFilter, year: .year(2025), currentYear: 2026, isPro: store.isPro) == false)

        store.setBetaProOverride(true)
        #expect(store.isPro == true)
        #expect(store.isEntitled == false)
        #expect(store.betaProOverride == true)
        for feature in ProFeature.allCases {
            #expect(ProGate.allows(feature, year: .year(2025), currentYear: 2026, isPro: store.isPro) == true,
                    "\(feature.rawValue): altes Jahr mit Freischaltung")
        }
        #expect(ProGate.allows(.statistics, year: .all, currentYear: 2026, isPro: store.isPro) == true)
        #expect(ProGate.allowsStatisticsDetail(isPro: store.isPro) == true)
        for kind in WidgetKind.allCases {
            #expect(ProGate.allowsWidget(kind, isPro: store.isPro) == true)
        }

        // Ein neuer Store (App-Neustart) und das Widget lesen denselben Wert.
        #expect(ProStore(betaDefaults: defaults).isPro == true)
        #expect(ProRules.unlocked(entitled: false, betaOverride: BetaSettings.proOverride(in: defaults)) == true)

        store.setBetaProOverride(false)
        #expect(store.isPro == false)
        #expect(ProGate.allowsStatisticsDetail(isPro: store.isPro) == false)
        #expect(ProGate.allowsWidget(.map, isPro: store.isPro) == false)
        #expect(ProStore(betaDefaults: defaults).isPro == false)
    }

    /// Ohne übergebene Defaults (Tests, Vorschauen) wirkt keine Freischaltung.
    @Test func storeWithoutDefaultsIgnoresOverride() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        BetaSettings.setProOverride(true, in: defaults)

        #expect(ProStore().isPro == false)
        #expect(ProStore(betaDefaults: nil).betaProOverride == false)
    }

    /// Ein echtes Abo bleibt unabhängig von der Freischaltung gültig.
    @Test func entitlementIndependentOfOverride() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ProStore(betaDefaults: defaults)
        let active = EntitlementFact(productID: "de.max.geoapp.pro.yearly", revoked: false,
                                     expires: betaNow.addingTimeInterval(30 * 86_400), isUpgraded: false)
        store.refresh(facts: [active], now: betaNow)
        #expect(store.isEntitled == true)
        #expect(store.isPro == true)

        store.setBetaProOverride(true)
        store.setBetaProOverride(false)
        #expect(store.isPro == true)

        store.refresh(facts: [], now: betaNow)
        #expect(store.isPro == false)
    }
    #endif

    @Test func testControlsVisibility() {
        #if DEBUG
        #expect(BetaSettings.showsTestControls(switchOn: true) == true)
        #expect(BetaSettings.showsTestControls(switchOn: false) == false)
        #else
        #expect(BetaSettings.showsTestControls(switchOn: false) == true)
        #endif
    }

    /// Release-Builds (App Store, TestFlight) setzen kein `DEBUG`; damit fehlen Beta-Menü und Pro-Freischaltung dort.
    /// Prüft `GeoApp.xcodeproj` und das Archiv-Schema neben dem Projekt.
    @Test func releaseBuildsHaveNoDebugFlag() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GeoAppTests
            .deletingLastPathComponent()   // GeoApp
        let project = try String(contentsOf: root.appendingPathComponent("GeoApp.xcodeproj/project.pbxproj"), encoding: .utf8)

        // Jeder Block nach `isa = XCBuildConfiguration;` endet mit `name = Debug;` oder `name = Release;`.
        let blocks = project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst()
        var releaseCount = 0
        var debugHasFlag = false
        for block in blocks {
            guard let nameRange = block.range(of: "name = ") else { continue }
            let settings = block[..<nameRange.lowerBound]
            let name = block[nameRange.upperBound...].prefix { $0 != ";" }
            let flagLines = settings.split(separator: "\n").filter {
                ($0.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS") || $0.contains("OTHER_SWIFT_FLAGS")) && $0.contains("DEBUG")
            }
            if name == "Release" {
                releaseCount += 1
                #expect(flagLines.isEmpty, "Release setzt DEBUG: \(flagLines)")
            } else if name == "Debug", !flagLines.isEmpty {
                debugHasFlag = true
            }
        }
        #expect(releaseCount >= 4, "Projekt und drei Ziele haben je eine Release-Konfiguration")
        #expect(debugHasFlag)

        let scheme = try String(contentsOf: root.appendingPathComponent("GeoApp.xcodeproj/xcshareddata/xcschemes/GeoApp.xcscheme"), encoding: .utf8)
        let archive = try #require(scheme.range(of: "<ArchiveAction"))
        let archiveTag = scheme[archive.lowerBound...].prefix { $0 != ">" }
        #expect(archiveTag.contains("buildConfiguration = \"Release\""))
    }
}
