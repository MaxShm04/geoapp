import Foundation
import Testing
@testable import GeoCore

struct TimePrivacyTests {
    /// Wortteile eines camelCase-Labels, kleingeschrieben (`longestTrip` → `longest`, `trip`).
    private func words(of label: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in label {
            if character.isUppercase, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.lowercased() }
    }

    /// Koordinaten-Begriffe in einem Feldnamen. `lat`/`lon` nur als eigenes Wort, damit `longestTrip` nicht zählt.
    private func leaksCoordinates(_ label: String) -> Bool {
        let lowered = label.lowercased()
        if ["coordinate", "location", "position", "latitude", "longitude"].contains(where: { lowered.contains($0) }) {
            return true
        }
        return words(of: label).contains { $0 == "lat" || $0 == "lon" }
    }

    @Test func valueTypesHaveNoCoordinates() {
        let values: [Any] = [
            PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159),
            Trip(startDay: 20260101, endDay: 20260103, dayCount: 3, countryCodes: ["DE"], mainCountryCode: "DE",
                 cityIds: [2950159], isOngoing: false),
            YearStatistics(year: 2026, countryCodes: ["DE"]),
            CountryDays(code: "DE", days: 3),
        ]

        for value in values {
            let typeName = String(describing: type(of: value))
            for label in Mirror(reflecting: value).children.compactMap(\.label) {
                #expect(!leaksCoordinates(label), "\(typeName).\(label) darf keine Koordinaten andeuten")
            }
        }
    }
}
