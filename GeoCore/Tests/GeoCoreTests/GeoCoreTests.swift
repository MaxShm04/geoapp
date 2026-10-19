import Foundation
import Testing
@testable import GeoCore

/// Feste Koordinaten gegen die echten Datensätze im Paket.
struct GeoLookupTests {
    let geo = GeoLookup.shared

    @Test func berlin() throws {
        let match = try #require(geo.resolve(latitude: 52.5200, longitude: 13.4050))
        #expect(match.countryCode == "DE")
        #expect(match.city?.name == "Berlin")
    }

    @Test func paris() throws {
        let match = try #require(geo.resolve(latitude: 48.8566, longitude: 2.3522))
        #expect(match.countryCode == "FR")
        #expect(match.city?.name == "Paris")
    }

    @Test func rome() throws {
        let match = try #require(geo.resolve(latitude: 41.9028, longitude: 12.4964))
        #expect(match.countryCode == "IT")
        #expect(match.city?.name == "Rome")
    }

    @Test func openSeaGivesNoResult() {
        #expect(geo.resolve(latitude: 30.0, longitude: -40.0) == nil)
    }

    /// Rhein zwischen Straßburg und Kehl, genau auf der Grenze.
    @Test func borderOnTheRhine() throws {
        let match = try #require(geo.resolve(latitude: 48.5717, longitude: 7.7997))
        #expect(["DE", "FR"].contains(match.countryCode))
        let city = try #require(match.city)
        #expect(["Strasbourg", "Kehl"].contains(city.name))
        #expect(city.countryCode == match.countryCode)
    }

    /// Etwa 2 km vor der Küste von Nizza: Die Küstentoleranz ordnet den Punkt Frankreich zu.
    @Test func justOffTheCoastOfNice() throws {
        let match = try #require(geo.resolve(latitude: 43.6760, longitude: 7.2700))
        #expect(match.countryCode == "FR")
        #expect(match.city?.name == "Nice")
    }

    @Test func monacoIsItsOwnCountry() throws {
        let match = try #require(geo.resolve(latitude: 43.7384, longitude: 7.4246))
        #expect(match.countryCode == "MC")
    }

    /// Überseegebiete sind eigene Gebiete wie bei ISO und GeoNames, sonst färbt Paris auch Südamerika ein.
    @Test(arguments: [
        (4.9224, -52.3135, "GF", "Cayenne"),
        (-20.8789, 55.4481, "RE", "Saint-Denis"),
        (14.6161, -61.0588, "MQ", "Fort-de-France"),
        (16.2650, -61.5510, "GP", nil),
        (-12.7806, 45.2279, "YT", "Mamoudzou"),
        (12.1443, -68.2655, "BQ", nil),
    ] as [(Double, Double, String, String?)])
    func overseasTerritories(lat: Double, lon: Double, code: String, city: String?) throws {
        let match = try #require(geo.resolve(latitude: lat, longitude: lon))
        #expect(match.countryCode == code)
        if let city { #expect(match.city?.name == city) }
    }

    /// Frankreich und die Niederlande enden in Europa.
    @Test func motherlandsStayInEurope() throws {
        for code in ["FR", "NL"] {
            let bounds = try #require(geo.countries.shape(for: code)?.bbox)
            #expect(bounds.minLon > -10 && bounds.minLat > 35, "\(code): \(bounds)")
        }
    }

    /// Petersdom. Kleinstaaten kommen aus 1:10m und haben Vorrang vor dem umgebenden Land.
    @Test func vatican() throws {
        let match = try #require(geo.resolve(latitude: 41.9033, longitude: 12.4535))
        #expect(match.countryCode == "VA")
        #expect(match.city?.name == "Vatican City")
    }

    /// Ohne Stadt im eigenen Land zählt die nächste Stadt eines anderen Landes im Radius.
    @Test func cityFromNeighbouringCountry() throws {
        let lookup = GeoLookup(
            countries: geo.countries,
            cities: CityIndex(cities: [
                City(id: 1, name: "Nachbarstadt", countryCode: "FR", latitude: 48.58, longitude: 7.75),
            ])
        )
        let match = try #require(lookup.resolve(latitude: 48.57, longitude: 7.82))
        #expect(match.countryCode == "DE")
        #expect(match.city?.name == "Nachbarstadt")
    }

    /// Lesotho ist ein Loch im Polygon von Südafrika.
    @Test func lesothoInsideSouthAfrica() throws {
        let match = try #require(geo.resolve(latitude: -29.3151, longitude: 27.4869))
        #expect(match.countryCode == "LS")
        #expect(match.city?.name == "Maseru")
    }

    /// Spandau liegt näher an Falkensee als an der Berliner Mitte, gehört aber zu Berlin.
    @Test func spandauCountsAsBerlin() throws {
        let match = try #require(geo.resolve(latitude: 52.5358, longitude: 13.2005))
        #expect(match.countryCode == "DE")
        #expect(match.city?.name == "Berlin")
    }

    /// Ein Arrondissement ergibt Paris, nicht "Paris 15 Vaugirard".
    @Test func arrondissementCountsAsParis() throws {
        let match = try #require(geo.resolve(latitude: 48.8417, longitude: 2.2986))
        #expect(match.city?.name == "Paris")
    }

    /// Isle of Dogs: Stadtteile wie Stepney gehören zur Großstadt London.
    @Test func canaryWharfCountsAsLondon() throws {
        let match = try #require(geo.resolve(latitude: 51.5054, longitude: -0.0235))
        #expect(match.countryCode == "GB")
        #expect(match.city?.name == "London")
    }

    @Test func midLevelsCountsAsHongKong() throws {
        let match = try #require(geo.resolve(latitude: 22.2820, longitude: 114.1490))
        #expect(match.city?.name == "Hong Kong")
    }

    @Test func brooklynCountsAsNewYork() throws {
        let match = try #require(geo.resolve(latitude: 40.6782, longitude: -73.9442))
        #expect(match.city?.name == "New York")
    }

    /// Eigenständige Städte neben Großstädten bleiben eigenständig.
    @Test(arguments: [
        (52.3906, 13.0645, "Potsdam"),
        (40.7357, -74.1724, "Newark"),
        (51.6565, -0.3903, "Watford"),
        (35.4437, 139.6380, "Yokohama"),
    ])
    func neighboursOfBigCitiesStayIndependent(lat: Double, lon: Double, name: String) throws {
        let match = try #require(geo.resolve(latitude: lat, longitude: lon))
        #expect(match.city?.name == name)
    }

    @Test func farFromAnyCityGivesCountryOnly() throws {
        // Mitten in der algerischen Sahara.
        let match = try #require(geo.resolve(latitude: 25.0, longitude: 3.0))
        #expect(match.countryCode == "DZ")
        #expect(match.city == nil)
        #expect(match.distanceToCityCenterKm == nil)
    }

    @Test func nearAntimeridian() throws {
        let match = try #require(geo.resolve(latitude: 64.8378, longitude: -147.7164))
        #expect(match.countryCode == "US")
        #expect(match.city?.name == "Fairbanks")
    }

    @Test(arguments: [
        (Double.nan, 13.4), (52.5, Double.nan), (95.0, 10.0), (-91.0, 10.0),
        (10.0, 181.0), (Double.infinity, 0.0), (90.0, 180.0), (-90.0, -180.0), (0.0, 0.0),
    ])
    func invalidOrExtremeInputNeverCrashes(lat: Double, lon: Double) {
        _ = geo.resolve(latitude: lat, longitude: lon)
    }

    @Test func invalidInputGivesNoResult() {
        #expect(geo.resolve(latitude: .nan, longitude: 13.4) == nil)
        #expect(geo.resolve(latitude: 95, longitude: 10) == nil)
    }

    @Test func dataIsComplete() {
        #expect(geo.countries.countries.count > 230)
        #expect(geo.cities.cities.count > 25_000)
        for code in ["DE", "FR", "NO", "XK", "MC", "VA", "SM", "LI", "AD"] {
            #expect(geo.countries.shape(for: code) != nil, "Land fehlt: \(code)")
        }
        // Die App gleicht gespeicherte Städte nur bei neuem Datenstand an.
        #expect(GeoLookup.dataVersion?.isEmpty == false)
    }

    /// Im Hintergrund hat die App nur wenige Sekunden. Laden und eine Abfrage müssen schnell gehen.
    @Test func loadAndLookupAreFast() throws {
        let start = Date()
        let fresh = try GeoLookup(bundle: .module)
        let loaded = Date().timeIntervalSince(start)
        let lookupStart = Date()
        for _ in 0..<100 { _ = fresh.resolve(latitude: 48.8566, longitude: 2.3522) }
        let perLookup = Date().timeIntervalSince(lookupStart) / 100
        print("Laden: \(Int(loaded * 1000)) ms, Abfrage: \(String(format: "%.2f", perLookup * 1000)) ms")
        #expect(loaded < 3)
        #expect(perLookup < 0.05)
    }
}
