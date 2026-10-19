import Foundation

/// Tage in einem Land.
public struct CountryDays: Sendable, Hashable {
    public var code: String
    public var days: Int

    public init(code: String, days: Int) {
        self.code = code
        self.days = days
    }
}

/// Statistik eines Jahres (oder aller Jahre bei `year == nil`).
public struct YearStatistics: Sendable {
    public var year: Int?
    public var countryCodes: Set<String>
    public var cityIds: Set<Int>
    /// Absteigend nach Tagen, bei Gleichstand nach Code.
    public var daysPerCountry: [CountryDays]
    /// Erstmals in diesem Jahr erfasst, nach erstem Tag sortiert.
    public var newCountryCodes: [String]
    public var newCityIds: [Int]
    /// Reisetage je Monat, Januar bis Dezember (bei `year == nil` über alle Jahre).
    public var travelDaysPerMonth: [Int]
    public var travelDays: Int
    public var longestTrip: Trip?
    /// Tage mit Daten (erfasst oder ergänzt).
    public var trackedDays: Int

    public init(year: Int?, countryCodes: Set<String> = [], cityIds: Set<Int> = [], daysPerCountry: [CountryDays] = [],
                newCountryCodes: [String] = [], newCityIds: [Int] = [],
                travelDaysPerMonth: [Int] = Array(repeating: 0, count: 12), travelDays: Int = 0,
                longestTrip: Trip? = nil, trackedDays: Int = 0) {
        self.year = year
        self.countryCodes = countryCodes
        self.cityIds = cityIds
        self.daysPerCountry = daysPerCountry
        self.newCountryCodes = newCountryCodes
        self.newCityIds = newCityIds
        self.travelDaysPerMonth = travelDaysPerMonth
        self.travelDays = travelDays
        self.longestTrip = longestTrip
        self.trackedDays = trackedDays
    }
}

public enum Statistics {
    /// `days` lückenlos (`GapFilling`), `trips` aus `TripDetector`.
    public static func make(year: Int?, days: [PlaceDay], trips: [Trip]) -> YearStatistics {
        func inScope(_ day: Int) -> Bool {
            year == nil || DayKey.year(day) == year
        }

        let scoped = days.filter { inScope($0.day) }
        let countryCodes = Set(scoped.map(\.countryCode))
        let cityIds = Set(scoped.compactMap(\.cityId))

        // Verschiedene Tage je Land
        var countryDays: [String: Set<Int>] = [:]
        for entry in scoped {
            countryDays[entry.countryCode, default: []].insert(entry.day)
        }
        let daysPerCountry = countryDays
            .map { CountryDays(code: $0.key, days: $0.value.count) }
            .sorted { $0.days != $1.days ? $0.days > $1.days : $0.code < $1.code }

        // Erster erfasster Tag je Land und Stadt, über alle Jahre
        var firstCountryDay: [String: Int] = [:]
        var firstCityDay: [Int: Int] = [:]
        for entry in days where !entry.isInferred {
            firstCountryDay[entry.countryCode] = min(firstCountryDay[entry.countryCode] ?? entry.day, entry.day)
            if let cityId = entry.cityId {
                firstCityDay[cityId] = min(firstCityDay[cityId] ?? entry.day, entry.day)
            }
        }
        let newCountryCodes = firstCountryDay
            .filter { inScope($0.value) }
            .sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .map { $0.key }
        let newCityIds = firstCityDay
            .filter { inScope($0.value) }
            .sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .map { $0.key }

        // Reisetage je Monat: jeder Kalendertag einer Reise zählt
        var travelDaysPerMonth = Array(repeating: 0, count: 12)
        for trip in trips {
            let span = DayKey.daysBetween(trip.startDay, trip.endDay)
            guard span >= 0 else { continue }
            for offset in 0...span {
                let day = DayKey.adding(offset, to: trip.startDay)
                if inScope(day) {
                    travelDaysPerMonth[DayKey.month(day) - 1] += 1
                }
            }
        }

        // Längste Reise unter den Reisen, die in dem Jahr beginnen
        let longestTrip = trips
            .filter { inScope($0.startDay) }
            .min { $0.dayCount != $1.dayCount ? $0.dayCount > $1.dayCount : $0.startDay < $1.startDay }

        return YearStatistics(
            year: year,
            countryCodes: countryCodes,
            cityIds: cityIds,
            daysPerCountry: daysPerCountry,
            newCountryCodes: newCountryCodes,
            newCityIds: newCityIds,
            travelDaysPerMonth: travelDaysPerMonth,
            travelDays: travelDaysPerMonth.reduce(0, +),
            longestTrip: longestTrip,
            trackedDays: Set(scoped.map(\.day)).count
        )
    }
}
