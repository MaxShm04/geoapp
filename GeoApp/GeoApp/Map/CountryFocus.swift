import Foundation
import GeoCore

/// Ein Stadtpunkt auf der Karte. Position ist die Stadtmitte laut GeoNames.
struct CityPin: Equatable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let regionId: String?
    let districtId: String?
    let population: Int
    /// An wie vielen verschiedenen Tagen die Stadt erfasst wurde.
    let days: Int

    /// Gut sichtbar mit Namen: größere Städte oder Orte, an denen man länger war.
    var isProminent: Bool {
        population >= CityImportance.minPopulation || days >= CityImportance.minDays
    }

    /// Reihenfolge, wenn sich Punkte überlappen: erst Aufenthaltsdauer, dann Größe.
    var importance: Float {
        Float(min(days, 30)) * 8 + Float(log10(Double(max(population, 1)))) * 10
    }
}

enum CityImportance {
    /// Ab dieser Einwohnerzahl ist eine Stadt immer mit Namen zu sehen.
    static let minPopulation = 50_000
    /// Ab so vielen verschiedenen Tagen gilt ein Aufenthalt als länger.
    static let minDays = 2
}

/// Alles, was die Länderansicht für ein Land braucht.
struct CountryFocus: Equatable {
    let code: String
    let pins: [CityPin]
    /// Besuchstage je Region und je Kreis, für die Abstufung der Farbe.
    let regionDays: [String: Int]
    let districtDays: [String: Int]

    /// Abstufung der Regionsfarbe: 0 unbesucht, 1 kurz, 2 mehrere Tage, 3 eine Woche und mehr.
    static func level(forDays days: Int) -> Int {
        switch days {
        case 0: 0
        case 1: 1
        case 2..<7: 2
        default: 3
        }
    }

    /// Baut den Fokus aus den gespeicherten Städten und Tagen eines Landes.
    ///
    /// Regionen und Kreise zählen nach den Tagen selbst (dort, wo man war). Ältere Einträge ohne
    /// gespeicherten Kreis zählen für den Kreis der Stadtmitte.
    static func make(code: String, cities: [City], visits: [DayVisit]) -> CountryFocus {
        let countryCities = cities.filter { $0.countryCode == code }
        let cityData = Dictionary(uniqueKeysWithValues: countryCities.map {
            ($0.geonamesId, GeoLookup.shared.cities.city(id: $0.geonamesId))
        })

        // Nach einem Daten-Update können gespeicherte Kreis-IDs veraltet sein. Dann zählt der Kreis
        // der Stadtmitte, denn die Position selbst ist nicht gespeichert.
        let knownDistricts = Set(DistrictIndex.shared.districts(in: code).map(\.id))

        var daysByCity: [Int: Set<Int>] = [:]
        var daysByRegion: [String: Set<Int>] = [:]
        var daysByDistrict: [String: Set<Int>] = [:]
        for visit in visits where visit.countryCode == code {
            let day = visit.day
            let fallback = visit.geonamesId.flatMap { cityData[$0] ?? nil }
            if let id = visit.geonamesId { daysByCity[id, default: []].insert(day) }
            if let region = visit.regionId ?? fallback?.regionId { daysByRegion[region, default: []].insert(day) }
            let stored = visit.districtId.flatMap { knownDistricts.contains($0) ? $0 : nil }
            if let district = stored ?? fallback?.districtId { daysByDistrict[district, default: []].insert(day) }
        }
        for city in countryCities {
            daysByCity[city.geonamesId, default: []].formUnion([
                VisitRules.dayKey(for: city.firstVisited), VisitRules.dayKey(for: city.lastVisited),
            ])
        }

        let pins = countryCities.map { city -> CityPin in
            let data = cityData[city.geonamesId] ?? nil
            return CityPin(id: city.geonamesId, name: PlaceNames.city(city),
                           latitude: city.centerLatitude, longitude: city.centerLongitude,
                           regionId: data?.regionId, districtId: data?.districtId,
                           population: data?.population ?? 0, days: daysByCity[city.geonamesId]?.count ?? 0)
        }
        return CountryFocus(code: code, pins: pins.sorted { $0.importance > $1.importance },
                            regionDays: daysByRegion.mapValues(\.count),
                            districtDays: daysByDistrict.mapValues(\.count))
    }
}
