import Foundation
import Testing
@testable import GeoApp

@MainActor
struct AccessibilityTests {
    @Test func mapSummary() {
        let en = Locale(identifier: "en")
        let de = Locale(identifier: "de")
        #expect(MapScreen.accessibilitySummary(countries: 5, cities: 12, locale: en)
                == "World map. 5 countries and 12 cities visited. The Trips tab lists all places.")
        #expect(MapScreen.accessibilitySummary(countries: 1, cities: 1, locale: en)
                == "World map. 1 country and 1 city visited. The Trips tab lists all places.")
        #expect(MapScreen.accessibilitySummary(countries: 5, cities: 12, locale: de)
                == "Weltkarte. 5 Länder und 12 Städte besucht. Der Tab „Reisen“ listet alle Orte auf.")
    }
}
