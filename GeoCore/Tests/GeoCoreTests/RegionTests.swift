import Foundation
import Testing
@testable import GeoCore

struct RegionTests {
    let regions = RegionIndex.shared
    let geo = GeoLookup.shared

    private func regionName(ofCity name: String, in cc: String) -> String? {
        geo.cities.cities.first { $0.name == name && $0.countryCode == cc }
            .flatMap(\.regionId)
            .flatMap { regions.region(id: $0)?.name }
    }

    /// Nicht zu fein: Deutschland in Bundesländer, Frankreich in Regionen statt 101 Départements.
    /// Spanien ohne Ceuta und Melilla: Die Regionen sind auf den Länderumriss (1:50m) zugeschnitten,
    /// und dort gibt es die beiden Städte nicht.
    @Test(arguments: [("DE", 16), ("FR", 18), ("GB", 12), ("US", 51), ("IT", 20), ("ES", 17)])
    func regionCounts(cc: String, expected: Int) {
        #expect(regions.regions(in: cc).count == expected)
    }

    @Test func smallCountriesHaveNoRegions() {
        for cc in ["MT", "LU", "HK", "SG", "MC", "VA"] {
            #expect(regions.regions(in: cc).isEmpty, "\(cc) sollte keine Regionen haben")
        }
    }

    @Test func citiesKnowTheirRegion() {
        #expect(regionName(ofCity: "London", in: "GB") == "Greater London")
        #expect(regionName(ofCity: "Edinburgh", in: "GB") == "Scotland")
        #expect(regionName(ofCity: "Paris", in: "FR") == "Île-de-France")
        #expect(regionName(ofCity: "Munich", in: "DE") == "Bayern")
        #expect(regionName(ofCity: "Los Angeles", in: "US") == "Kalifornien")
    }

    @Test func regionAtPoint() {
        #expect(regions.region(in: "DE", lat: 48.14, lon: 11.58)?.name == "Bayern")
        #expect(regions.region(in: "DE", lat: 30.0, lon: -40.0) == nil)
    }

    @Test func citiesCarryPopulation() {
        let london = geo.cities.cities.first { $0.name == "London" && $0.countryCode == "GB" }
        #expect((london?.population ?? 0) > 5_000_000)
    }

    @Test func loadingIsFastEnough() throws {
        let url = try #require(Bundle.module.url(forResource: "regions.json", withExtension: "z"))
        let start = Date()
        let index = try RegionIndex(jsonData: inflate(Data(contentsOf: url)))
        let seconds = Date().timeIntervalSince(start)
        print("Regionen laden: \(Int(seconds * 1000)) ms")
        #expect(!index.regions(in: "DE").isEmpty)
        #expect(seconds < 3)
    }
}

struct DistrictTests {
    let districts = DistrictIndex.shared
    let geo = GeoLookup.shared

    @Test func germanyHasLandkreise() {
        let german = districts.districts(in: "DE")
        #expect(german.count > 400)
        let bavaria = RegionIndex.shared.region(in: "DE", lat: 48.14, lon: 11.58)
        let bavarian = german.filter { $0.regionId == bavaria?.id }
        #expect(bavarian.count > 90)   // 71 Landkreise und 25 kreisfreie Städte
    }

    @Test func franceUsesDepartements() {
        #expect((90...105).contains(districts.districts(in: "FR").count))
    }

    @Test func citiesKnowTheirDistrict() throws {
        let munich = try #require(geo.cities.cities.first { $0.name == "Munich" && $0.countryCode == "DE" })
        let district = try #require(munich.districtId.flatMap { districts.district(id: $0) })
        #expect(district.name.contains("München"))
        #expect(district.regionId == munich.regionId)
    }

    @Test func smallCountriesHaveNoDistricts() {
        #expect(districts.districts(in: "LU").isEmpty)
        #expect(districts.districts(in: "XX").isEmpty)
    }

    @Test func sourcesAreListed() {
        let sources = districts.sources
        #expect(sources.contains { $0.cc == "DE" && $0.license.contains("Germany") })
    }

    @Test func loadingOneCountryIsFast() {
        let start = Date()
        let index = DistrictIndex(bundle: .module)
        let count = index.districts(in: "US").count
        let seconds = Date().timeIntervalSince(start)
        print("Kreise USA laden: \(count) in \(Int(seconds * 1000)) ms")
        #expect(seconds < 2)
    }
}

/// Region und Kreis kommen von der Position, nicht von der Stadtmitte.
struct AreaAtPositionTests {
    let geo = GeoLookup.shared

    private func districtName(_ match: GeoMatch?) -> String? {
        match?.districtId.flatMap { DistrictIndex.shared.district(id: $0)?.name }
    }

    /// Großstädte sind nicht unterteilt: Ganz London ist eine Zone, vom Zentrum bis an den Rand.
    @Test(arguments: [(51.4995, -0.0195), (51.4995, -0.1248), (51.5607, 0.2193), (51.5300, -0.4300)])
    func londonIsOneZone(lat: Double, lon: Double) throws {
        let match = try #require(geo.resolve(latitude: lat, longitude: lon))
        #expect(districtName(match) == "London")
        #expect(match.regionId.flatMap { RegionIndex.shared.region(id: $0)?.name } == "Greater London")
    }

    @Test func newYorkIsOneZone() throws {
        let manhattan = try #require(geo.resolve(latitude: 40.7831, longitude: -73.9712))
        let brooklyn = try #require(geo.resolve(latitude: 40.6782, longitude: -73.9442))
        #expect(districtName(manhattan) == "New York City")
        #expect(manhattan.districtId == brooklyn.districtId)
    }

    @Test func ruralPointGetsRegionAndDistrict() throws {
        // Altmühltal, mitten in Bayern
        let match = try #require(geo.resolve(latitude: 49.0, longitude: 11.3))
        #expect(match.countryCode == "DE")
        #expect(match.regionId.flatMap { RegionIndex.shared.region(id: $0)?.name } == "Bayern")
        #expect(match.districtId != nil)
    }

    @Test func withoutAreasStaysLight() throws {
        let match = try #require(geo.resolve(latitude: 51.4995, longitude: -0.0195, includeAreas: false))
        #expect(match.districtId == nil && match.regionId == nil)
    }
}

struct MapDetailTests {
    @Test func londonHasMainRoads() throws {
        let index = CityDetailIndex.shared
        let london = try #require(GeoLookup.shared.cities.cities.first { $0.name == "London" && $0.countryCode == "GB" })
        let detail = try #require(index.detail(for: london.id))
        #expect(detail.roads.contains { $0.roadClass == .motorway })
        let visible = BoundingBox(minLat: 51.45, minLon: -0.2, maxLat: 51.55, maxLon: 0.0)
        #expect(index.cities(intersecting: visible).contains(london.id))
    }
}
