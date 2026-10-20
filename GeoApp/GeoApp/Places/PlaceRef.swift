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

    /// Verschiedene Tage an diesem Ort, neueste zuerst.
    func days(in visits: [DayVisit]) -> [Int] {
        PlaceCalendar.distinctDays(matching(visits).map(\.day))
    }

    /// Städte je Tag innerhalb dieses Orts, für die Kalender-Blase und die Liste der Aufenthalte.
    func placesByDay(in visits: [DayVisit]) -> [Int: DayPlaces] {
        Dictionary(grouping: matching(visits), by: \.day).mapValues { dayVisits in
            var places = DayPlaces()
            for visit in dayVisits.sorted(by: { $0.firstSeen < $1.firstSeen }) {
                if let id = visit.geonamesId {
                    if !places.cityIds.contains(id) { places.cityIds.append(id) }
                } else {
                    places.countryOnly = true
                }
            }
            return places
        }
    }

    /// Tageseinträge an diesem Ort. Ohne gespeicherte (oder mit veralteter) Region bzw. Kreis zählt der
    /// der Stadtmitte, wie auf der Karte (`CountryFocus`).
    private func matching(_ visits: [DayVisit]) -> [DayVisit] {
        switch self {
        case .city(let id):
            return visits.filter { $0.geonamesId == id }
        case .country(let code):
            return visits.filter { $0.countryCode == code }
        case .region(let id):
            return visits.filter { ($0.regionId ?? Self.cityCenter(of: $0)?.regionId) == id }
        case .district(let id):
            let country = String(id.split(separator: ":").first ?? "")
            let known = Set(DistrictIndex.shared.districts(in: country).map(\.id))
            return visits.filter { visit in
                guard visit.countryCode == country else { return false }
                let stored = visit.districtId.flatMap { known.contains($0) ? $0 : nil }
                return (stored ?? Self.cityCenter(of: visit)?.districtId) == id
            }
        }
    }

    private static func cityCenter(of visit: DayVisit) -> GeoCore.City? {
        visit.geonamesId.flatMap { GeoLookup.shared.cities.city(id: $0) }
    }
}

/// Die Städte eines Tages (oder Aufenthalts) an einem Ort, in der Reihenfolge des ersten Besuchs.
/// `countryOnly`: mindestens ein Eintrag ohne Stadt in der Nähe.
struct DayPlaces: Equatable {
    var cityIds: [Int] = []
    var countryOnly = false

    /// Alle Städte mehrerer Tage, ohne Doppelte.
    static func merged(_ days: [DayPlaces]) -> DayPlaces {
        var result = DayPlaces()
        for day in days {
            for id in day.cityIds where !result.cityIds.contains(id) { result.cityIds.append(id) }
            result.countryOnly = result.countryOnly || day.countryOnly
        }
        return result
    }

    /// „Munich and Hamburg“, ab vier Städten „Munich, Hamburg, Berlin and 2 more“, ohne Stadt „No city nearby“.
    func text(locale: Locale = .current, name: ((Int) -> String)? = nil) -> String {
        let name = name ?? { PlaceNames.city(id: $0) }
        guard !cityIds.isEmpty else { return L10n.string("No city nearby", locale: locale) }
        let shown = cityIds.count > 3 ? Array(cityIds.prefix(3)) : cityIds
        if shown.count < cityIds.count {
            let list = shown.map(name).joined(separator: ", ")
            return L10n.string("\(list) and \(cityIds.count - shown.count) more", locale: locale)
        }
        return shown.map(name).formatted(.list(type: .and).locale(locale))
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
