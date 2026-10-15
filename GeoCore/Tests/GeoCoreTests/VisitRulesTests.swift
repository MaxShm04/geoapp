import Foundation
import Testing
@testable import GeoCore

struct VisitRulesTests {
    @Test func validPositionPasses() {
        #expect(VisitRules.rejectReason(horizontalAccuracy: 65, speed: 1.2) == nil)
        #expect(VisitRules.rejectReason(horizontalAccuracy: 10_000, speed: -1) == nil)
    }

    @Test func negativeAccuracyIsInvalid() {
        #expect(VisitRules.rejectReason(horizontalAccuracy: -1, speed: 0) == .invalidAccuracy)
        #expect(VisitRules.rejectReason(horizontalAccuracy: .nan, speed: 0) == .invalidAccuracy)
    }

    @Test func accuracyOverTenKilometersIsIgnored() {
        #expect(VisitRules.rejectReason(horizontalAccuracy: 10_001, speed: 0) == .inaccurate)
    }

    @Test func flightIsIgnoredButTrainAndCarCount() {
        #expect(VisitRules.rejectReason(horizontalAccuracy: 100, speed: 250) == .flight)
        #expect(VisitRules.rejectReason(horizontalAccuracy: 100, speed: 83) == nil)   // ICE, 300 km/h
        #expect(VisitRules.rejectReason(horizontalAccuracy: 100, speed: 150) == nil)  // Grenzwert zählt noch
    }

    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    @Test func dayKeyIsTheLocalDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC
        let utc = calendar("UTC")
        #expect(VisitRules.dayKey(for: date, calendar: utc) == 2027_01_15)
        // Derselbe Tag bis kurz vor Mitternacht, danach der nächste.
        #expect(VisitRules.dayKey(for: date.addingTimeInterval(15 * 3600 + 59 * 60), calendar: utc) == 2027_01_15)
        #expect(VisitRules.dayKey(for: date.addingTimeInterval(16 * 3600), calendar: utc) == 2027_01_16)
    }

    @Test func dayKeyFollowsTheTimeZoneAtCapture() {
        // Derselbe Augenblick ist in Tokio schon der nächste Tag, in Los Angeles noch der vorige.
        let date = Date(timeIntervalSince1970: 1_800_000_000 + 12 * 3600)  // 2027-01-15 20:00 UTC
        #expect(VisitRules.dayKey(for: date, calendar: calendar("UTC")) == 2027_01_15)
        #expect(VisitRules.dayKey(for: date, calendar: calendar("Asia/Tokyo")) == 2027_01_16)
        #expect(VisitRules.dayKey(for: date.addingTimeInterval(-16 * 3600), calendar: calendar("America/Los_Angeles")) == 2027_01_14)
    }
}
