import Foundation
import GeoCore
import SwiftData
import Testing
@testable import GeoApp

/// Ordner `GeoApp/` (Xcode-Projekt), abgeleitet aus diesem Dateipfad: `GeoApp/GeoAppTests/<Datei>.swift`.
private let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// Die `strings` des Kurzbefehl-Katalogs (D11). Fehlt die Datei, wird ein Issue gemeldet.
private func loadShortcutStrings() -> [String: Any]? {
    let url = projectDirectory.appendingPathComponent("GeoApp/AppShortcuts.xcstrings")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else {
        Issue.record("AppShortcuts.xcstrings fehlt oder ist kein gültiger String-Katalog: \(url.path)")
        return nil
    }
    return strings
}

/// Der deutsche `stringUnit.value` eines Katalogeintrags.
private func germanValue(_ entry: [String: Any]?) -> String? {
    guard let localizations = entry?["localizations"] as? [String: Any],
          let german = localizations["de"] as? [String: Any],
          let unit = german["stringUnit"] as? [String: Any] else { return nil }
    return unit["value"] as? String
}

@MainActor
struct IntentTests {
    let en = Locale(identifier: "en")
    let de = Locale(identifier: "de")

    @Test func countriesThisYearAnswer() {
        #expect(CountriesThisYearIntent.answer(count: 5, year: 2026, locale: en) == "You’ve been to 5 countries in 2026.")
        #expect(CountriesThisYearIntent.answer(count: 1, year: 2026, locale: en) == "You’ve been to 1 country in 2026.")
        #expect(CountriesThisYearIntent.answer(count: 0, year: 2026, locale: en) == "No countries recorded in 2026 yet.")
        #expect(CountriesThisYearIntent.answer(count: 5, year: 2026, locale: de) == "Du warst 2026 in 5 Ländern.")
        #expect(CountriesThisYearIntent.answer(count: 1, year: 2026, locale: de) == "Du warst 2026 in 1 Land.")
        #expect(CountriesThisYearIntent.answer(count: 0, year: 2026, locale: de) == "2026 ist noch kein Land erfasst.")
    }

    @Test func countriesThisYearCount() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let entries = [
            DayVisits.Entry(day: 20260105, countryCode: "DE", geonamesId: 2867714, regionId: nil, districtId: nil,
                            timestamp: timestamp, source: .visit),
            DayVisits.Entry(day: 20260210, countryCode: "IT", geonamesId: 3169070, regionId: nil, districtId: nil,
                            timestamp: timestamp, source: .visit),
            DayVisits.Entry(day: 20260211, countryCode: "IT", geonamesId: 3169070, regionId: nil, districtId: nil,
                            timestamp: timestamp, source: .visit),
            DayVisits.Entry(day: 20251231, countryCode: "FR", geonamesId: 2988507, regionId: nil, districtId: nil,
                            timestamp: timestamp, source: .visit),
        ]
        for entry in entries {
            _ = DayVisits.add(entry, context: context)
        }
        try context.save()

        #expect(CountriesThisYearIntent.count(context: context, year: 2026) == 2)
        #expect(CountriesThisYearIntent.count(context: context, year: 2025) == 1)
    }

    @Test func shortcutPhrasesLocalized() {
        guard let strings = loadShortcutStrings() else { return }
        #expect(!strings.isEmpty, "AppShortcuts.xcstrings has no keys")

        let placeholder = "${applicationName}"
        var offending: [String] = []
        for key in strings.keys.sorted() {
            let german = germanValue(strings[key] as? [String: Any]) ?? ""
            if !key.contains(placeholder) || !german.contains(placeholder) {
                offending.append(key)
            }
        }
        #expect(offending.isEmpty, "Shortcut phrases without ${applicationName} in key or de value: \(offending.joined(separator: ", "))")
    }
}
