import Foundation
import GeoCore
import Testing
@testable import GeoApp

/// Der Snapshot für die Widgets: Zahlen, Namen und Zeitpunkt, nie Koordinaten (D8).
struct WidgetSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Schlüssel, die auf eine Position hindeuten: `lat` und `lon` als ganze Wörter (camelCase oder mit
    /// Trennzeichen), sonst `latitude`, `longitude`, `coordinate`, `location`, `position` als Wortteil.
    nonisolated static func isCoordinateKey(_ key: String) -> Bool {
        var spaced = ""
        var previous: Character?
        for character in key {
            if character.isUppercase, let before = previous, before.isLowercase || before.isNumber {
                spaced.append(" ")
            }
            spaced.append(character.isLetter || character.isNumber ? character : " ")
            previous = character
        }
        let words = spaced.lowercased().split(separator: " ").map(String.init)
        if words.contains("lat") || words.contains("lon") { return true }
        let lowered = key.lowercased()
        return ["latitude", "longitude", "coordinate", "location", "position"].contains { lowered.contains($0) }
    }

    @Test func countsTotalsAndYear() {
        let days = [
            PlaceDay(day: 20250610, countryCode: "DE", cityId: 2950159),   // Berlin
            PlaceDay(day: 20260105, countryCode: "DE", cityId: 2867714),   // München
            PlaceDay(day: 20260210, countryCode: "IT", cityId: 3169070),   // Rom
            PlaceDay(day: 20260301, countryCode: "FR"),                    // nur das Land
        ]
        let snapshot = WidgetSnapshot.make(days: days, today: 20260519, cityName: { "City \($0)" }, now: now)
        #expect(snapshot.year == 2026)
        #expect(snapshot.countriesTotal == 3)
        #expect(snapshot.citiesTotal == 3)
        #expect(snapshot.countriesThisYear == 3)
        #expect(snapshot.citiesThisYear == 2)
        #expect(snapshot.newCountriesThisYear == 2)
        #expect(snapshot.newCitiesThisYear == 2)
        #expect(snapshot.updated == now)
    }

    @Test func newPlaceNamesNewestFirst() {
        let days = [
            PlaceDay(day: 20260102, countryCode: "DE", cityId: 1),                    // A
            PlaceDay(day: 20260203, countryCode: "DE", cityId: 2),                    // B
            PlaceDay(day: 20260304, countryCode: "DE", cityId: 3),                    // C
            PlaceDay(day: 20260405, countryCode: "DE", cityId: 4),                    // D
            PlaceDay(day: 20250601, countryCode: "DE", cityId: 5),                    // 2025 zuerst, 2026 wieder
            PlaceDay(day: 20260120, countryCode: "DE", cityId: 5),
            PlaceDay(day: 20260515, countryCode: "DE", cityId: 6, isInferred: true),  // ergänzt, zählt nicht als neu
        ]
        let snapshot = WidgetSnapshot.make(days: days, today: 20260519, cityName: { "City \($0)" }, now: now)
        #expect(snapshot.newPlaceNames == ["City 4", "City 3", "City 2"])
    }

    @Test func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = WidgetSnapshot.url(in: directory)
        #expect(url == directory.appendingPathComponent("widget-snapshot.json"))

        #expect(WidgetSnapshot.load(from: url) == nil)

        try WidgetSnapshot.placeholder.write(to: url)
        #expect(WidgetSnapshot.load(from: url) == WidgetSnapshot.placeholder)

        try Data("kein json".utf8).write(to: url)
        #expect(WidgetSnapshot.load(from: url) == nil)
    }

    @Test func noCoordinatesInSnapshot() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.placeholder)
        let parsed = try JSONSerialization.jsonObject(with: data)
        let object = try #require(parsed as? [String: Any])
        let keys = Array(object.keys)
        #expect(keys.filter(WidgetSnapshotTests.isCoordinateKey).isEmpty)

        let labels = Mirror(reflecting: WidgetSnapshot.placeholder).children.compactMap(\.label)
        #expect(labels.filter(WidgetSnapshotTests.isCoordinateKey).isEmpty)
    }
}
