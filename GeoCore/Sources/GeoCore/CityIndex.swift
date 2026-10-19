import Foundation

/// Eine Stadt aus GeoNames `cities15000`. Die Stadtmitte stammt aus dem Datensatz,
/// nie aus der Position der Person.
public struct City: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let countryCode: String
    public let latitude: Double
    public let longitude: Double
    /// Einwohner laut GeoNames, inklusive zugeordneter Stadtteile.
    public let population: Int
    /// Region (Bundesland, Staat, Provinz) aus `regions.json.z`, leer in Ländern ohne Regionen.
    public let regionId: String?
    /// Kreis (Landkreis, Département, County) aus `Districts/`, leer in Ländern ohne Kreise.
    public let districtId: String?

    public init(id: Int, name: String, countryCode: String, latitude: Double, longitude: Double,
                population: Int = 0, regionId: String? = nil, districtId: String? = nil) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.population = population
        self.regionId = regionId
        self.districtId = districtId
    }
}

/// Nächste-Stadt-Suche über ein Raster aus 1°-Zellen.
///
/// Neben der Stadtmitte hat eine Stadt oft weitere Bezugspunkte (Stadtteile, Arrondissements
/// aus GeoNames). So landet ein Punkt am Stadtrand von Berlin bei Berlin und nicht beim
/// näheren Nachbarort.
public struct CityIndex: Sendable {
    private struct Point: Sendable {
        let city: Int
        let lat: Double
        let lon: Double
    }

    public let cities: [City]
    private let cells: [Int: [Point]]
    private let byID: [Int: Int]

    public init(cities: [City], extraPoints: [(cityID: Int, lat: Double, lon: Double)] = []) {
        self.cities = cities
        let byID = Dictionary(cities.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.byID = byID
        var cells: [Int: [Point]] = [:]
        for (index, city) in cities.enumerated() {
            cells[Self.cell(lat: city.latitude, lon: city.longitude), default: []]
                .append(Point(city: index, lat: city.latitude, lon: city.longitude))
        }
        for extra in extraPoints {
            guard let index = byID[extra.cityID] else { continue }
            cells[Self.cell(lat: extra.lat, lon: extra.lon), default: []]
                .append(Point(city: index, lat: extra.lat, lon: extra.lon))
        }
        self.cells = cells
    }

    public func city(id: Int) -> City? {
        byID[id].map { cities[$0] }
    }

    /// Name der Stadt in `language` aus `city_names.tsv`, sonst der eigene Name der Stadt.
    /// `nil` nur bei unbekannter ID. Die Übersetzungen werden erst beim ersten Aufruf geladen.
    public func localizedName(id: Int, language: String) -> String? {
        guard let city = city(id: id) else { return nil }
        return cityNameTable[id]?[normalizedLanguageCode(language)] ?? city.name
    }

    /// Nächste Stadt innerhalb von `radiusKm`. Städte aus `preferredCountry` haben Vorrang,
    /// erst wenn dort keine im Radius liegt, zählt eine Stadt aus einem anderen Land.
    public func nearest(lat: Double, lon: Double, radiusKm: Double, preferredCountry: String?) -> City? {
        var bestPreferred: (city: Int, km: Double)?
        var bestAny: (city: Int, km: Double)?

        let latCells = Int((radiusKm / 110.574).rounded(.up))
        let cosLat = max(cos(lat * .pi / 180), 0.01)
        let lonCells = min(Int((radiusKm / (111.320 * cosLat)).rounded(.up)), 180)
        let baseLat = Int(floor(lat)), baseLon = Int(floor(lon))

        for dLat in -latCells...latCells {
            let cellLat = baseLat + dLat
            guard cellLat >= -90, cellLat < 90 else { continue }
            for dLon in -lonCells...lonCells {
                var cellLon = baseLon + dLon
                if cellLon < -180 { cellLon += 360 }
                if cellLon >= 180 { cellLon -= 360 }
                guard let points = cells[Self.cellKey(lat: cellLat, lon: cellLon)] else { continue }
                for point in points {
                    let km = haversineKm(lat1: lat, lon1: lon, lat2: point.lat, lon2: point.lon)
                    guard km <= radiusKm else { continue }
                    if km < bestAny?.km ?? .infinity { bestAny = (point.city, km) }
                    if let preferredCountry, cities[point.city].countryCode == preferredCountry,
                       km < bestPreferred?.km ?? .infinity {
                        bestPreferred = (point.city, km)
                    }
                }
            }
        }
        return (bestPreferred ?? bestAny).map { cities[$0.city] }
    }

    private static func cell(lat: Double, lon: Double) -> Int {
        cellKey(lat: Int(floor(lat)), lon: Int(floor(lon)))
    }

    private static func cellKey(lat: Int, lon: Int) -> Int {
        (lat + 90) * 360 + (lon + 180)
    }
}

/// Übersetzte Stadtnamen aus `city_names.tsv` (geonameid, Sprache, Name). Nur Namen, die vom
/// englischen Namen abweichen. Swift lädt globale `let` beim ersten Zugriff, thread-sicher und
/// einmal pro Prozess, `GeoLookup.shared` lädt sie nicht.
private let cityNameTable: [Int: [String: String]] = {
    guard let url = Bundle.module.url(forResource: "city_names", withExtension: "tsv"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var table: [Int: [String: String]] = [:]
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard cols.count == 3, let id = Int(cols[0]) else { continue }
        table[id, default: [:]][String(cols[1])] = String(cols[2])
    }
    return table
}()

/// Sprachcode ohne Region und in Kleinbuchstaben: `de-DE` und `pt_BR` werden zu `de` und `pt`.
func normalizedLanguageCode(_ identifier: String) -> String {
    let parts = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" })
    return parts.first.map(String.init) ?? ""
}

extension CityIndex {
    /// Liest `cities.tsv` aus `tools/build_data.py`: id, parent, cc, lat, lon, name, einwohner, region, kreis.
    /// Zeilen mit parent sind zusätzliche Bezugspunkte der Stadt mit dieser ID.
    public init(tsv: String) {
        var cities: [City] = []
        var extras: [(cityID: Int, lat: Double, lon: Double)] = []
        cities.reserveCapacity(32_000)
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 6, let id = Int(cols[0]),
                  let lat = Double(cols[3]), let lon = Double(cols[4]) else { continue }
            if let parent = Int(cols[1]) {
                extras.append((parent, lat, lon))
            } else {
                let population = cols.count > 6 ? Int(cols[6]) ?? 0 : 0
                let region = cols.count > 7 && !cols[7].isEmpty ? String(cols[7]) : nil
                let district = cols.count > 8 && !cols[8].isEmpty ? String(cols[8]) : nil
                cities.append(City(id: id, name: String(cols[5]), countryCode: String(cols[2]),
                                   latitude: lat, longitude: lon, population: population,
                                   regionId: region, districtId: district))
            }
        }
        self.init(cities: cities, extraPoints: extras)
    }
}
