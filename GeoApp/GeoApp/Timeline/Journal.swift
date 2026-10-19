import Foundation
import GeoCore

extension PlaceDay {
    /// Ein gespeicherter Tageseintrag als Wert. Übernimmt nur IDs, Tag und Zeitpunkt.
    init(_ visit: DayVisit) {
        self.init(day: visit.day, countryCode: visit.countryCode, cityId: visit.geonamesId, regionId: visit.regionId,
                  lastSeen: visit.lastSeen)
    }
}

/// Reisetagebuch aus den gespeicherten Tagen: lückenlose Tage, Heimatregion und Reisen.
/// Wird bei der Anzeige berechnet und nie gespeichert (Entscheidung D2).
struct Journal {
    /// Lückenlos (`GapFilling`).
    let days: [PlaceDay]
    /// Heimatgebiet: Auswahl in den Einstellungen, sonst erkannt.
    let home: String?
    let detectedHome: String?
    /// Neueste zuerst.
    let trips: [Trip]

    static let empty = Journal(days: [], home: nil, detectedHome: nil, trips: [])

    static func make(visits: [DayVisit], homeOverride: String?, today: Int) -> Journal {
        let days = GapFilling.fill(visits.map(PlaceDay.init), through: today)
        let detected = HomeRegion.detect(days, today: today)
        let home = homeOverride.flatMap { $0.isEmpty ? nil : $0 } ?? detected
        let trips = home.map { TripDetector.trips(in: days, home: $0, today: today) } ?? []
        return Journal(days: days, home: home, detectedHome: detected, trips: trips.reversed())
    }

    /// Jahre mit Daten, absteigend, das laufende Jahr immer dabei.
    func years(currentYear: Int) -> [Int] {
        YearFilter.availableYears(days: days.map(\.day), currentYear: currentYear)
    }

    func statistics(year: Int?) -> YearStatistics {
        Statistics.make(year: year, days: days, trips: trips)
    }
}
