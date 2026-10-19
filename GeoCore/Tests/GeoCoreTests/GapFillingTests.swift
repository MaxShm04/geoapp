import Foundation
import Testing
@testable import GeoCore

struct GapFillingTests {
    /// Zeitpunkt für `lastSeen`: Stunden nach dem Beginn der Unixzeit.
    private func at(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: 0).addingTimeInterval(hours * 3600)
    }

    @Test func emptyStaysEmpty() {
        #expect(GapFilling.fill([], through: 20260110) == [])
    }

    @Test func fillsGapWithLastPlace() {
        let berlin = PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")
        let rome = PlaceDay(day: 20260104, countryCode: "IT", cityId: 3169070, regionId: "IT-LAZ")
        let out = GapFilling.fill([berlin, rome], through: 20260104)

        #expect(out.count == 4)
        #expect(out.map { $0.day } == [20260101, 20260102, 20260103, 20260104])
        for day in [20260102, 20260103] {
            let filled = out.filter { $0.day == day }
            #expect(filled.count == 1)
            #expect(filled.first?.countryCode == "DE")
            #expect(filled.first?.cityId == 2950159)
            #expect(filled.first?.regionId == "DE-BE")
            #expect(filled.first?.isInferred == true)
        }
        #expect(out.filter { !$0.isInferred } == [berlin, rome])
    }

    @Test func lastSeenPlaceOfTheDayWins() {
        let munich = PlaceDay(day: 20260101, countryCode: "DE", cityId: 2867714, regionId: "DE-BY", lastSeen: at(8))
        let salzburg = PlaceDay(day: 20260101, countryCode: "AT", cityId: 2766824, regionId: "AT-SBG", lastSeen: at(18))
        let munichAgain = PlaceDay(day: 20260103, countryCode: "DE", cityId: 2867714, regionId: "DE-BY", lastSeen: at(8))
        let out = GapFilling.fill([munich, salzburg, munichAgain], through: 20260103)

        let inferred = out.filter { $0.isInferred }
        #expect(inferred.map { $0.day } == [20260102])
        #expect(inferred.first?.countryCode == "AT")
        #expect(inferred.first?.cityId == 2766824)
    }

    @Test func fillsUpToToday() {
        let berlin = PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")

        let filled = GapFilling.fill([berlin], through: 20260104)
        #expect(filled.filter { $0.isInferred }.map { $0.day } == [20260102, 20260103, 20260104])
        #expect(filled.count == 4)

        #expect(GapFilling.fill([berlin], through: 20260101).allSatisfy { !$0.isInferred })
        #expect(GapFilling.fill([berlin], through: 20251231).allSatisfy { !$0.isInferred })
    }

    @Test func longGapIsNotFilled() {
        #expect(GapFilling.maxGapDays == 30)

        let start = PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")
        let monthLater = PlaceDay(day: 20260201, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")
        let thirtyDays = GapFilling.fill([start, monthLater], through: 20260201)
        #expect(thirtyDays.filter { $0.isInferred }.count == 30)

        let thirtyOneDays = PlaceDay(day: 20260202, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")
        let tooLong = GapFilling.fill([start, thirtyOneDays], through: 20260202)
        #expect(tooLong.filter { $0.isInferred }.count == 0)
    }

    @Test func capturedDaysAreNeverDuplicated() {
        let captured = [
            PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159, regionId: "DE-BE"),
            PlaceDay(day: 20260102, countryCode: "DE", cityId: 2950159, regionId: "DE-BE"),
            PlaceDay(day: 20260102, countryCode: "DE", cityId: 2911298, regionId: "DE-HH"),
            PlaceDay(day: 20260103, countryCode: "DE", cityId: 2950159, regionId: "DE-BE"),
        ]
        let out = GapFilling.fill(captured, through: 20260103)

        #expect(out.count == 4)
        #expect(out.allSatisfy { !$0.isInferred })
    }

    @Test func trailingGapRespectsMax() {
        let berlin = PlaceDay(day: 20260101, countryCode: "DE", cityId: 2950159, regionId: "DE-BE")
        let out = GapFilling.fill([berlin], through: 20260301)
        #expect(out.filter { $0.isInferred }.count == 0)
    }
}
