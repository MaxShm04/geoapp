import Foundation

/// Ein Land mit seinen Grenzen aus Natural Earth.
public struct CountryShape: Sendable {
    /// ISO-3166-Alpha-2-Code, bei wenigen Gebieten ohne ISO-Code der Natural-Earth-Code.
    public let code: String
    /// Englischer Name aus Natural Earth, als Rückfall für die Anzeige.
    public let name: String
    public let polygons: [Polygon]
    public let bbox: BoundingBox
}

/// Ordnet Koordinaten per Punkt-in-Polygon einem Land zu.
public struct CountryIndex: Sendable {
    public let countries: [CountryShape]
    private let byCode: [String: Int]

    public init(countries: [CountryShape]) {
        // Kleine Länder zuerst: Liegt der Vatikan ungenau im Polygon von Italien, gewinnt der Vatikan.
        let countries = countries.sorted { $0.bbox.area < $1.bbox.area }
        self.countries = countries
        self.byCode = Dictionary(countries.enumerated().map { ($1.code, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func shape(for code: String) -> CountryShape? {
        byCode[code].map { countries[$0] }
    }

    /// Land, in dessen Grenzen der Punkt liegt. Liegt er knapp außerhalb (vor der Küste oder
    /// durch die vereinfachten Grenzen), zählt das nächste Land innerhalb von `toleranceKm`.
    public func country(lat: Double, lon: Double, toleranceKm: Double) -> CountryShape? {
        for country in countries where country.bbox.contains(lat: lat, lon: lon) {
            if country.polygons.contains(where: { $0.contains(lat: lat, lon: lon) }) {
                return country
            }
        }
        guard toleranceKm > 0 else { return nil }
        var best: (country: CountryShape, km: Double)?
        for country in countries where country.bbox.contains(lat: lat, lon: lon, marginKm: toleranceKm) {
            for polygon in country.polygons where polygon.bbox.contains(lat: lat, lon: lon, marginKm: toleranceKm) {
                let km = polygon.distanceToEdgeKm(lat: lat, lon: lon)
                if km <= toleranceKm, km < best?.km ?? .infinity {
                    best = (country, km)
                }
            }
        }
        return best?.country
    }
}

extension CountryIndex {
    private struct File: Decodable {
        struct Country: Decodable {
            let code: String
            let name: String
            let polygons: [[[Double]]]
        }
        let countries: [Country]
    }

    /// Liest `countries.json` aus `tools/build_data.py`.
    public init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        let shapes = file.countries.map { country -> CountryShape in
            let polygons = country.polygons.map(Polygon.init(rings:))
            let bbox = polygons.dropFirst().reduce(polygons.first?.bbox ?? BoundingBox(minLat: 0, minLon: 0, maxLat: 0, maxLon: 0)) {
                $0.union($1.bbox)
            }
            return CountryShape(code: country.code, name: country.name, polygons: polygons, bbox: bbox)
        }
        self.init(countries: shapes)
    }
}
