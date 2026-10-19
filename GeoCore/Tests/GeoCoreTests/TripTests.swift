import Foundation
import Testing
@testable import GeoCore

struct TripTests {
    private struct Spot {
        let countryCode: String
        let cityId: Int
        let regionId: String
    }

    private let munich = Spot(countryCode: "DE", cityId: 2867714, regionId: "DE-BY")
    private let hamburg = Spot(countryCode: "DE", cityId: 2911298, regionId: "DE-HH")
    private let salzburg = Spot(countryCode: "AT", cityId: 2766824, regionId: "AT-SBG")
    private let verona = Spot(countryCode: "IT", cityId: 3164527, regionId: "IT-VEN")
    private let venice = Spot(countryCode: "IT", cityId: 3164603, regionId: "IT-VEN")
    private let florence = Spot(countryCode: "IT", cityId: 3176959, regionId: "IT-TOS")
    private let rome = Spot(countryCode: "IT", cityId: 3169070, regionId: "IT-LAZ")
    private let zurich = Spot(countryCode: "CH", cityId: 2657896, regionId: "CH-ZH")

    /// Ein Eintrag an diesem Tag um `hour` Uhr.
    private func place(_ day: Int, _ spot: Spot, at hour: Double = 12) -> PlaceDay {
        PlaceDay(day: day, countryCode: spot.countryCode, cityId: spot.cityId, regionId: spot.regionId,
                 lastSeen: Date(timeIntervalSince1970: 0).addingTimeInterval(hour * 3600))
    }

    /// Ein Eintrag je Tag von `first` bis `last`, beide eingeschlossen.
    private func stay(_ first: Int, through last: Int, _ spot: Spot) -> [PlaceDay] {
        dayKeys(from: first, through: last).map { place($0, spot) }
    }

    /// yyyymmdd-Schlüssel aller Tage von `first` bis `last` (gregorianisch, UTC).
    private func dayKeys(from first: Int, through last: Int) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ key: Int) -> Date {
            calendar.date(from: DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100))!
        }
        var keys: [Int] = []
        var current = date(first)
        let end = date(last)
        while current <= end {
            let parts = calendar.dateComponents([.year, .month, .day], from: current)
            keys.append(parts.year! * 10000 + parts.month! * 100 + parts.day!)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return keys
    }

    /// Munich 20260501…20260511, Munich/Verona 20260512, Verona 20260513, Venice 20260514–15,
    /// Florence 20260516–17, Rome 20260518, Rome/Munich 20260519, Munich 20260520.
    private func overnightTripDays() -> [PlaceDay] {
        var days: [PlaceDay] = []
        days += stay(20260501, through: 20260511, munich)
        days += [place(20260512, munich, at: 8), place(20260512, verona, at: 18)]
        days += stay(20260513, through: 20260513, verona)
        days += stay(20260514, through: 20260515, venice)
        days += stay(20260516, through: 20260517, florence)
        days += [place(20260518, rome)]
        days += [place(20260519, rome, at: 9), place(20260519, munich, at: 20)]
        days += [place(20260520, munich)]
        return days
    }

    /// Munich 20260510, Verona 20260512–13, Verona 20260515–16 (no entry on 20260514), Munich 20260517.
    private func missingDayDays() -> [PlaceDay] {
        var days: [PlaceDay] = []
        days += [place(20260510, munich)]
        days += stay(20260512, through: 20260513, verona)
        days += stay(20260515, through: 20260516, verona)
        days += [place(20260517, munich)]
        return days
    }

    @Test func overnightTripIsDetected() throws {
        let trips = TripDetector.trips(in: overnightTripDays(), home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.startDay == 20260512)
        #expect(trip.endDay == 20260519)
        #expect(trip.dayCount == 8)
        #expect(trip.mainCountryCode == "IT")
        #expect(trip.countryCodes == ["IT"])
        #expect(trip.cityIds == [3164527, 3164603, 3176959, 3169070])
        #expect(trip.isOngoing == false)
    }

    @Test func dayTripIsNoTrip() {
        var days: [PlaceDay] = []
        days += [place(20260509, munich)]
        days += [place(20260510, munich, at: 8), place(20260510, salzburg, at: 12), place(20260510, munich, at: 20)]
        days += [place(20260511, munich)]
        let trips = TripDetector.trips(in: days, home: "DE-BY", today: 20260525)
        #expect(trips == [])
    }

    @Test func domesticTripOutsideHomeRegion() throws {
        var days: [PlaceDay] = []
        days += [place(20260501, munich)]
        days += stay(20260502, through: 20260503, hamburg)
        days += [place(20260504, munich)]
        let trips = TripDetector.trips(in: days, home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.startDay == 20260502)
        #expect(trip.endDay == 20260503)
        #expect(trip.countryCodes == ["DE"])
        #expect(trip.mainCountryCode == "DE")
        #expect(trip.cityIds == [2911298])
    }

    @Test func multiCountryOrderByDays() throws {
        // Salzburg 2 Tage, Verona 4 Tage, Zurich 1 Tag
        var days: [PlaceDay] = []
        days += [place(20260501, munich)]
        days += stay(20260502, through: 20260503, salzburg)
        days += stay(20260504, through: 20260507, verona)
        days += [place(20260508, zurich)]
        days += [place(20260509, munich)]
        let trips = TripDetector.trips(in: days, home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.countryCodes == ["IT", "AT", "CH"])
        #expect(trip.mainCountryCode == "IT")

        // Salzburg 2 Tage, Verona 2 Tage: Gleichstand, erster Besuch gewinnt
        var tieDays: [PlaceDay] = []
        tieDays += [place(20260501, munich)]
        tieDays += stay(20260502, through: 20260503, salzburg)
        tieDays += stay(20260504, through: 20260505, verona)
        tieDays += [place(20260506, munich)]
        let tieTrips = TripDetector.trips(in: tieDays, home: "DE-BY", today: 20260525)
        try #require(tieTrips.count == 1)
        let tieTrip = try #require(tieTrips.first)
        #expect(tieTrip.countryCodes == ["AT", "IT"])
    }

    @Test func ongoingTrip() throws {
        var days: [PlaceDay] = []
        days += [place(20260520, munich)]
        days += stay(20260521, through: 20260525, verona)
        let trips = TripDetector.trips(in: days, home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.endDay == 20260525)
        #expect(trip.isOngoing == true)
    }

    @Test func missingDayBreaksTrip() throws {
        let trips = TripDetector.trips(in: missingDayDays(), home: "DE-BY", today: 20260525)
        try #require(trips.count == 2)
        #expect(trips[0].startDay == 20260512)
        #expect(trips[0].endDay == 20260513)
        #expect(trips[1].startDay == 20260515)
        #expect(trips[1].endDay == 20260516)
    }

    @Test func homeCitiesNotCounted() throws {
        let trips = TripDetector.trips(in: overnightTripDays(), home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(!trip.cityIds.contains(2867714))
    }

    @Test func inferredDaysCount() throws {
        var days: [PlaceDay] = []
        days += [place(20260501, munich)]
        days += [place(20260512, munich, at: 8), place(20260512, verona, at: 18)]
        days += [place(20260516, verona, at: 9), place(20260516, munich, at: 20)]
        let filled = GapFilling.fill(days, through: 20260516)
        let trips = TripDetector.trips(in: filled, home: "DE-BY", today: 20260525)
        try #require(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.startDay == 20260512)
        #expect(trip.endDay == 20260516)
        #expect(trip.dayCount == 5)
    }

    @Test func sortedAndEmpty() throws {
        // Umgekehrte Eingabe, damit die Sortierung wirklich geprüft wird.
        let trips = TripDetector.trips(in: missingDayDays().reversed(), home: "DE-BY", today: 20260525)
        try #require(trips.count == 2)
        #expect(trips.map(\.startDay) == [20260512, 20260515])

        #expect(TripDetector.trips(in: [], home: "DE-BY", today: 20260525) == [])

        let homeOnly = stay(20260501, through: 20260503, munich)
        #expect(TripDetector.trips(in: homeOnly, home: "DE-BY", today: 20260525) == [])
    }
}
