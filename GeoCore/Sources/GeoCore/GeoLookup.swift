import Foundation

/// Ergebnis einer Zuordnung. Enthält nur Werte aus den Datensätzen, keine Position der Person.
public struct GeoMatch: Sendable, Equatable {
    public let countryCode: String
    public let city: City?
    /// Entfernung zur Stadtmitte laut GeoNames, für das Diagnose-Log.
    public let distanceToCityCenterKm: Double?
    /// Region und Kreis an der Position selbst, nicht an der Stadtmitte: Wer kurz hinter der
    /// Stadtgrenze steht, zählt für die Stadt, aber für den Landkreis, in dem er steht. Leer,
    /// wenn das Land keine Unterteilung hat.
    public let regionId: String?
    public let districtId: String?

    public init(countryCode: String, city: City?, distanceToCityCenterKm: Double?,
                regionId: String? = nil, districtId: String? = nil) {
        self.countryCode = countryCode
        self.city = city
        self.distanceToCityCenterKm = distanceToCityCenterKm
        self.regionId = regionId
        self.districtId = districtId
    }
}

/// Offline-Zuordnung von Koordinate zu Land und Stadt.
public final class GeoLookup: Sendable {
    /// Suchradius für die nächste Stadt. Startwert laut Briefing, nach dem Alltagstest anpassen.
    public static let cityRadiusKm = 25.0
    /// Liegt ein Punkt knapp außerhalb aller Grenzen, gilt das nächste Land in dieser Entfernung.
    public static let coastToleranceKm = 5.0

    /// Lädt die Daten aus dem Paket beim ersten Zugriff, danach bleiben sie im Speicher.
    public static let shared: GeoLookup = {
        do {
            return try GeoLookup(bundle: .module)
        } catch {
            fatalError("GeoCore-Daten fehlen im App-Paket: \(error)")
        }
    }()

    /// Stand der Datensätze aus `data_version.txt` (siehe tools/build_data.py). Liest nur diese
    /// kleine Datei, lädt keine Grenzen oder Städte.
    public static let dataVersion: String? = Bundle.module.url(forResource: "data_version", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    public let countries: CountryIndex
    public let cities: CityIndex

    public init(countries: CountryIndex, cities: CityIndex) {
        self.countries = countries
        self.cities = cities
    }

    convenience init(bundle: Bundle) throws {
        guard let countriesURL = bundle.url(forResource: "countries", withExtension: "json"),
              let citiesURL = bundle.url(forResource: "cities", withExtension: "tsv") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let countries = try CountryIndex(jsonData: Data(contentsOf: countriesURL))
        let cities = try CityIndex(tsv: String(contentsOf: citiesURL, encoding: .utf8))
        self.init(countries: countries, cities: cities)
    }

    /// Land per Polygon, Stadt per Radius. Ohne Stadt im Radius zählt nur das Land.
    /// Liegt der Punkt in keinem Land (offenes Meer) oder ist er ungültig, gibt es kein Ergebnis.
    /// `includeAreas`: auch Region und Kreis bestimmen (lädt deren Grenzen beim ersten Mal).
    public func resolve(latitude: Double, longitude: Double, includeAreas: Bool = true) -> GeoMatch? {
        guard let code = countryCode(latitude: latitude, longitude: longitude) else { return nil }
        let city = cities.nearest(lat: latitude, lon: longitude,
                                  radiusKm: Self.cityRadiusKm, preferredCountry: code)
        let distance = city.map {
            haversineKm(lat1: latitude, lon1: longitude, lat2: $0.latitude, lon2: $0.longitude)
        }
        let district = includeAreas ? DistrictIndex.shared.district(in: code, lat: latitude, lon: longitude) : nil
        let region = district.map(\.regionId).flatMap { $0.isEmpty ? nil : $0 }
            ?? (includeAreas ? RegionIndex.shared.region(in: code, lat: latitude, lon: longitude)?.id : nil)
        return GeoMatch(countryCode: code, city: city, distanceToCityCenterKm: distance,
                        regionId: region, districtId: district?.id)
    }

    /// Nur das Land, etwa für einen Tipp auf die Karte.
    public func countryCode(latitude: Double, longitude: Double) -> String? {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return nil }
        return countries.country(lat: latitude, lon: longitude, toleranceKm: Self.coastToleranceKm)?.code
    }

    static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}
