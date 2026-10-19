import Foundation
import GeoCore

extension WidgetSnapshot {
    /// Zahlen für die Widgets aus den erfassten Tagen (ohne ergänzte Tage).
    static func make(days: [PlaceDay], today: Int, cityName: (Int) -> String, now: Date) -> WidgetSnapshot {
        let year = DayKey.year(today)
        let thisYear = days.filter { DayKey.year($0.day) == year }

        // Gesamt: alle Tage, auch ergänzte, die nur bekannte Orte wiederholen.
        let countriesTotal = Set(days.map(\.countryCode)).count
        let citiesTotal = Set(days.compactMap(\.cityId)).count
        let countriesThisYear = Set(thisYear.map(\.countryCode)).count
        let citiesThisYear = Set(thisYear.compactMap(\.cityId)).count

        // Neu: erster erfasster Tag je Land und Stadt. Ergänzte Tage zählen nie als neu.
        let captured = days.filter { !$0.isInferred }
        var firstCountryDay: [String: Int] = [:]
        var firstCityDay: [Int: Int] = [:]
        for place in captured {
            firstCountryDay[place.countryCode] = min(firstCountryDay[place.countryCode] ?? .max, place.day)
            if let cityId = place.cityId {
                firstCityDay[cityId] = min(firstCityDay[cityId] ?? .max, place.day)
            }
        }
        let newCountries = firstCountryDay.values.filter { DayKey.year($0) == year }
        let newCities = firstCityDay.filter { DayKey.year($0.value) == year }
        // Neueste zuerst, bei gleichem Tag die höhere ID zuerst.
        let newPlaceNames = newCities
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }
            .prefix(3)
            .map { cityName($0.key) }

        return WidgetSnapshot(year: year, countriesTotal: countriesTotal, citiesTotal: citiesTotal,
                              countriesThisYear: countriesThisYear, citiesThisYear: citiesThisYear,
                              newCountriesThisYear: newCountries.count, newCitiesThisYear: newCities.count,
                              newPlaceNames: newPlaceNames, updated: now)
    }
}
