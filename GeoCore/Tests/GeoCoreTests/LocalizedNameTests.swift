import Testing
@testable import GeoCore

struct LocalizedNameTests {
    let geo = GeoLookup.shared

    private static let rome = 3_169_070
    private static let potsdam = 2_852_458
    private static let munich = 2_867_714

    @Test func cityGerman() {
        #expect(geo.cities.localizedName(id: Self.rome, language: "de") == "Rom")
    }

    @Test func cityEnglishDefault() {
        #expect(geo.cities.localizedName(id: Self.rome, language: "en") == "Rome")
        #expect(geo.cities.localizedName(id: Self.rome, language: "xx") == "Rome")
    }

    @Test func cityWithoutTranslation() throws {
        let potsdam = try #require(geo.cities.city(id: Self.potsdam))
        #expect(geo.cities.localizedName(id: Self.potsdam, language: "de") == potsdam.name)
    }

    @Test func cityMunichFrench() {
        #expect(geo.cities.localizedName(id: Self.munich, language: "fr") == "Munich")
        #expect(geo.cities.localizedName(id: Self.munich, language: "de") == "München")
        #expect(geo.cities.localizedName(id: Self.munich, language: "it") == "Monaco di Baviera")
    }

    @Test func regionGermanEnglish() throws {
        let bavaria = try #require(RegionIndex.shared.region(in: "DE", lat: 48.14, lon: 11.58))
        #expect(bavaria.localizedName(language: "de") == "Bayern")
        #expect(bavaria.localizedName(language: "en") == "Bavaria")
    }

    @Test func regionFallback() throws {
        let bavaria = try #require(RegionIndex.shared.region(in: "DE", lat: 48.14, lon: 11.58))
        #expect(bavaria.localizedName(language: "xx") == "Bavaria")
    }
}
