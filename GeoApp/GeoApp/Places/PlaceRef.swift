import Foundation
import GeoCore

/// Ein Ort für die Ortsansicht: Stadt, Kreis, Region oder Land. Nur IDs aus den Datensätzen, keine Positionen.
enum PlaceRef: Hashable, Identifiable {
    case city(Int)
    case district(String)
    case region(String)
    case country(String)

    var id: String {
        switch self {
        case .city(let id): "city:\(id)"
        case .district(let id): "district:\(id)"
        case .region(let id): "region:\(id)"
        case .country(let code): "country:\(code)"
        }
    }

    /// Einzeln löschen lassen sich nur Städte und Länder (`Deletion`).
    var canDelete: Bool {
        switch self {
        case .city, .country: true
        case .district, .region: false
        }
    }

    /// Name in der Gerätesprache.
    var name: String {
        switch self {
        case .city(let id): PlaceNames.city(id: id)
        case .district(let id): DistrictIndex.shared.district(id: id)?.name ?? id
        case .region(let id): PlaceNames.region(id: id, fallback: id)
        case .country(let code): CountryNames.name(for: code)
        }
    }

    /// Wo der Ort liegt: das Land, beim Kreis die Region.
    var context: String? {
        switch self {
        case .city(let id):
            GeoLookup.shared.cities.city(id: id).map { CountryNames.name(for: $0.countryCode) }
        case .district(let id):
            DistrictIndex.shared.district(id: id).map { PlaceNames.region(id: $0.regionId, fallback: $0.regionId) }
        case .region(let id):
            RegionIndex.shared.region(id: id).map { CountryNames.name(for: $0.countryCode) }
        case .country:
            nil
        }
    }

    /// Verschiedene Tage an diesem Ort, neueste zuerst. Ohne gespeicherte (oder mit veralteter) Region
    /// bzw. Kreis zählt der der Stadtmitte, wie auf der Karte (`CountryFocus`).
    func days(in visits: [DayVisit]) -> [Int] {
        let matching: [DayVisit]
        switch self {
        case .city(let id):
            matching = visits.filter { $0.geonamesId == id }
        case .country(let code):
            matching = visits.filter { $0.countryCode == code }
        case .region(let id):
            matching = visits.filter { ($0.regionId ?? Self.cityCenter(of: $0)?.regionId) == id }
        case .district(let id):
            let country = String(id.split(separator: ":").first ?? "")
            let known = Set(DistrictIndex.shared.districts(in: country).map(\.id))
            matching = visits.filter { visit in
                guard visit.countryCode == country else { return false }
                let stored = visit.districtId.flatMap { known.contains($0) ? $0 : nil }
                return (stored ?? Self.cityCenter(of: visit)?.districtId) == id
            }
        }
        return PlaceCalendar.distinctDays(matching.map(\.day))
    }

    private static func cityCenter(of visit: DayVisit) -> GeoCore.City? {
        visit.geonamesId.flatMap { GeoLookup.shared.cities.city(id: $0) }
    }
}

/// Was die Ortsansicht zeigt. Ohne Pro nur das aktuelle Jahr, wie bei den Reisen (`ProGate`, `.timeline`).
struct PlaceDays: Equatable {
    /// Freie Jahre mit ihren Aufenthalten, neuestes zuerst.
    let years: [YearStays]
    /// Jahre mit Besuchen, die Pro brauchen.
    let lockedYears: [Int]
    /// Tage der freien Jahre, neueste zuerst.
    let shownDays: [Int]
    /// Alle Tage, auch gesperrte Jahre.
    let totalDays: Int

    /// Monate mit Besuchen in den freien Jahren, neueste zuerst.
    var months: [Int] { PlaceCalendar.months(days: shownDays) }

    static func make(days: [Int], currentYear: Int, isPro: Bool) -> PlaceDays {
        let distinct = PlaceCalendar.distinctDays(days)
        let allowed = { (year: Int) in
            ProGate.allows(.timeline, year: .year(year), currentYear: currentYear, isPro: isPro)
        }
        let byYear = PlaceCalendar.staysByYear(days: distinct)
        return PlaceDays(years: byYear.filter { allowed($0.year) },
                         lockedYears: byYear.map(\.year).filter { !allowed($0) },
                         shownDays: distinct.filter { allowed(DayKey.year($0)) },
                         totalDays: distinct.count)
    }
}
