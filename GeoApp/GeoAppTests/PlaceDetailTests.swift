import Foundation
import GeoCore
import Testing
@testable import GeoApp

private let munichID = 2867714
private let salzburgID = 2766824

private func visit(_ day: Int, _ country: String, city: Int? = nil, region: String? = nil, district: String? = nil,
                   hour: Double = 0) -> DayVisit {
    let at = Date(timeIntervalSince1970: hour * 3600)
    let key = [String(day), country, city.map(String.init) ?? "-", district ?? region ?? "-", "real"].joined(separator: "|")
    return DayVisit(key: key, day: day, countryCode: country, geonamesId: city, regionId: region, districtId: district,
                    firstSeen: at, lastSeen: at, captureCount: 1, sourceMask: 1, isDemo: false)
}

/// Ortsansicht: welche Tage zu einem Ort gehören und welche Jahre ohne Pro zu sehen sind.
@MainActor
struct PlaceDetailTests {
    @Test func cityAndCountryDays() {
        let visits = [
            visit(20260510, "DE", city: munichID, region: "DE-BY"),
            visit(20260510, "DE", city: munichID, region: "DE-BY", district: "DE:other"),
            visit(20260511, "DE", city: munichID),
            visit(20260512, "AT", city: salzburgID),
            visit(20260513, "DE"),
        ]
        #expect(PlaceRef.city(munichID).days(in: visits) == [20260511, 20260510])
        #expect(PlaceRef.city(salzburgID).days(in: visits) == [20260512])
        #expect(PlaceRef.country("DE").days(in: visits) == [20260513, 20260511, 20260510])
        #expect(PlaceRef.country("FR").days(in: visits) == [])
    }

    /// Ohne gespeicherte Region zählt die Region der Stadtmitte, wie auf der Karte (`CountryFocus`).
    @Test func regionFallsBackToCityCenter() throws {
        let munichRegion = try #require(GeoLookup.shared.cities.city(id: munichID)?.regionId)
        let visits = [
            visit(20260101, "DE", city: munichID, region: munichRegion),
            visit(20260102, "DE", city: munichID),
            visit(20260103, "DE", region: "DE-somewhere-else"),
        ]
        #expect(PlaceRef.region(munichRegion).days(in: visits) == [20260102, 20260101])
    }

    @Test func districtDays() throws {
        let munichDistrict = try #require(GeoLookup.shared.cities.city(id: munichID)?.districtId)
        let visits = [
            visit(20260201, "DE", city: munichID, district: munichDistrict),
            // Kein Kreis gespeichert: Kreis der Stadtmitte.
            visit(20260202, "DE", city: munichID),
            // Veralteter Kreis nach einem Daten-Update: ebenfalls Kreis der Stadtmitte.
            visit(20260203, "DE", city: munichID, district: "DE:does-not-exist"),
            visit(20260204, "DE", district: "DE:does-not-exist"),
        ]
        #expect(PlaceRef.district(munichDistrict).days(in: visits) == [20260203, 20260202, 20260201])
    }

    @Test func onlyCitiesAndCountriesCanBeDeleted() {
        #expect(PlaceRef.city(munichID).canDelete)
        #expect(PlaceRef.country("DE").canDelete)
        #expect(!PlaceRef.region("DE-BY").canDelete)
        #expect(!PlaceRef.district("DE:x").canDelete)
    }

    @Test func identity() {
        let all: [PlaceRef] = [.city(1), .district("DE:1"), .region("1"), .country("DE")]
        #expect(Set(all.map(\.id)).count == 4)
        #expect(PlaceRef.city(1).id == PlaceRef.city(1).id)
    }

    /// Ohne Pro nur das aktuelle Jahr, frühere Jahre gesperrt (Gate `.timeline`, wie Reisen).
    @Test func freeShowsCurrentYearOnly() {
        let days = [20260105, 20260104, 20250720, 20240101]
        let free = PlaceDays.make(days: days, currentYear: 2026, isPro: false)
        #expect(free.years.map(\.year) == [2026])
        #expect(free.lockedYears == [2025, 2024])
        #expect(free.shownDays == [20260105, 20260104])
        #expect(free.totalDays == 4)

        let pro = PlaceDays.make(days: days, currentYear: 2026, isPro: true)
        #expect(pro.years.map(\.year) == [2026, 2025, 2024])
        #expect(pro.lockedYears == [])
        #expect(pro.shownDays == [20260105, 20260104, 20250720, 20240101])
        #expect(pro.months == [202601, 202507, 202401])
    }

    @Test func freeWithOnlyPastYears() {
        let free = PlaceDays.make(days: [20250720], currentYear: 2026, isPro: false)
        #expect(free.years.isEmpty)
        #expect(free.lockedYears == [2025])
        #expect(free.months.isEmpty)
    }

    @Test func emptyPlace() {
        let empty = PlaceDays.make(days: [], currentYear: 2026, isPro: false)
        #expect(empty.years.isEmpty && empty.lockedYears.isEmpty && empty.totalDays == 0)
    }

    /// Städte je Tag für Kalender-Blase und Liste: in der Reihenfolge des ersten Besuchs, nur innerhalb des Orts.
    @Test func placesByDay() {
        let hamburg = 2911298, berlin = 2950159
        let visits = [
            visit(20260510, "DE", city: hamburg, hour: 14),
            visit(20260510, "DE", city: munichID, hour: 8),
            visit(20260510, "AT", city: salzburgID, hour: 11),
            visit(20260511, "DE"),
            visit(20260512, "DE", city: berlin, hour: 9),
            visit(20260512, "DE", hour: 18),
        ]
        let byDay = PlaceRef.country("DE").placesByDay(in: visits)
        #expect(byDay[20260510] == DayPlaces(cityIds: [munichID, hamburg], countryOnly: false))
        #expect(byDay[20260511] == DayPlaces(cityIds: [], countryOnly: true))
        #expect(byDay[20260512] == DayPlaces(cityIds: [berlin], countryOnly: true))
        #expect(byDay.count == 3)

        #expect(PlaceRef.city(munichID).placesByDay(in: visits) == [20260510: DayPlaces(cityIds: [munichID], countryOnly: false)])

        let merged = DayPlaces.merged([byDay[20260510]!, byDay[20260511]!, byDay[20260512]!])
        #expect(merged == DayPlaces(cityIds: [munichID, hamburg, berlin], countryOnly: true))
    }

    /// Text unter einem Aufenthalt und in der Blase: Städtenamen, sonst „keine Stadt in der Nähe“.
    @Test func dayPlacesText() {
        let en = Locale(identifier: "en")
        let de = Locale(identifier: "de")
        let name = { (id: Int) in ["1": "Munich", "2": "Hamburg", "3": "Berlin", "4": "Bonn", "5": "Kiel"][String(id)] ?? "?" }
        #expect(DayPlaces(cityIds: [1], countryOnly: false).text(locale: en, name: name) == "Munich")
        #expect(DayPlaces(cityIds: [1, 2], countryOnly: true).text(locale: en, name: name) == "Munich and Hamburg")
        #expect(DayPlaces(cityIds: [1, 2, 3, 4, 5], countryOnly: false).text(locale: en, name: name)
                == "Munich, Hamburg, Berlin and 2 more")
        #expect(DayPlaces(cityIds: [], countryOnly: true).text(locale: en, name: name) == "No city nearby")
        #expect(DayPlaces(cityIds: [], countryOnly: true).text(locale: de, name: name) == "Keine Stadt in der Nähe")
        #expect(DayPlaces(cityIds: [1, 2], countryOnly: false).text(locale: de, name: name) == "Munich und Hamburg")
    }

    /// Suche in der Liste: Groß- und Kleinschreibung und Akzente egal, Städte auch über ihr Land.
    @Test func searchMatches() {
        #expect(PlacesList.matches("", "Berlin"))
        #expect(PlacesList.matches("münch", "München"))
        #expect(PlacesList.matches("MUNCHEN", "München"))
        #expect(PlacesList.matches(" rom ", "Rom"))
        #expect(PlacesList.matches("ital", "Rom", "Italien"))
        #expect(!PlacesList.matches("paris", "Rom", "Italien"))
    }

    /// Wochentage im Kalender beginnen mit `firstWeekday`.
    @Test func weekdaySymbolsRotate() {
        var monday = Calendar(identifier: .gregorian)
        monday.locale = Locale(identifier: "de_DE")
        monday.firstWeekday = 2
        let symbols = MonthGrid.weekdaySymbols(calendar: monday)
        #expect(symbols.count == 7)
        #expect(symbols.first == monday.veryShortStandaloneWeekdaySymbols[1])
        #expect(symbols.last == monday.veryShortStandaloneWeekdaySymbols[0])

        var sunday = Calendar(identifier: .gregorian)
        sunday.locale = Locale(identifier: "en_US")
        sunday.firstWeekday = 1
        #expect(MonthGrid.weekdaySymbols(calendar: sunday) == sunday.veryShortStandaloneWeekdaySymbols)
    }
}
