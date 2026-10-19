import Foundation

/// Eine Reise: aufeinanderfolgende Tage außerhalb des Heimatgebiets mit mindestens einer Nacht weg.
public struct Trip: Sendable, Hashable, Identifiable {
    public var startDay: Int
    public var endDay: Int
    public var dayCount: Int
    /// Länder außerhalb des Heimatgebiets, nach Tagen absteigend.
    public var countryCodes: [String]
    public var mainCountryCode: String
    /// Städte außerhalb des Heimatgebiets in der Reihenfolge des ersten Besuchs.
    public var cityIds: [Int]
    public var isOngoing: Bool

    public var id: Int { startDay }

    public init(startDay: Int, endDay: Int, dayCount: Int, countryCodes: [String], mainCountryCode: String,
                cityIds: [Int], isOngoing: Bool) {
        self.startDay = startDay
        self.endDay = endDay
        self.dayCount = dayCount
        self.countryCodes = countryCodes
        self.mainCountryCode = mainCountryCode
        self.cityIds = cityIds
        self.isOngoing = isOngoing
    }
}

public enum TripDetector {
    /// Reisen in `days` (lückenlos), aufsteigend nach Beginn.
    public static func trips(in days: [PlaceDay], home: String, today: Int) -> [Trip] {
        // Einträge nach Tag und letztem Besuch sortiert, unabhängig von der Eingabereihenfolge.
        let sorted = days.sorted { lhs, rhs in
            (lhs.day, lhs.lastSeen, lhs.countryCode, lhs.cityId ?? 0)
                < (rhs.day, rhs.lastSeen, rhs.countryCode, rhs.cityId ?? 0)
        }
        let entriesByDay = Dictionary(grouping: sorted, by: \.day)

        // Läufe aufeinanderfolgender Tage mit mindestens einem Eintrag außerhalb des Heimatgebiets.
        var runs: [[Int]] = []
        var run: [Int] = []
        for day in entriesByDay.keys.sorted() {
            guard entriesByDay[day, default: []].contains(where: { area($0) != home }) else { continue }
            if let last = run.last, DayKey.daysBetween(last, day) != 1 {
                runs.append(run)
                run = []
            }
            run.append(day)
        }
        if !run.isEmpty { runs.append(run) }

        return runs.compactMap { runDays in
            // Mindestens eine Nacht weg: ein Tag ganz ohne Eintrag im Heimatgebiet.
            let hasNightAway = runDays.contains { day in
                !entriesByDay[day, default: []].contains { area($0) == home }
            }
            guard hasNightAway else { return nil }
            return trip(days: runDays, entriesByDay: entriesByDay, home: home, today: today)
        }
    }

    /// Gebiet für Heimatregion und Reisen: die Region, ohne Region das Land.
    private static func area(_ place: PlaceDay) -> String {
        place.regionId ?? place.countryCode
    }

    /// Reise über die aufeinanderfolgenden Tage `days`, nur Einträge außerhalb des Heimatgebiets zählen.
    private static func trip(days: [Int], entriesByDay: [Int: [PlaceDay]], home: String, today: Int) -> Trip? {
        let outside = days.flatMap { entriesByDay[$0, default: []] }.filter { area($0) != home }

        var countryOrder: [String] = []
        var countryDays: [String: Set<Int>] = [:]
        var cityIds: [Int] = []
        for place in outside {
            if countryDays[place.countryCode] == nil { countryOrder.append(place.countryCode) }
            countryDays[place.countryCode, default: []].insert(place.day)
            if let cityId = place.cityId, !cityIds.contains(cityId) { cityIds.append(cityId) }
        }
        let countryCodes = countryOrder.enumerated().sorted { lhs, rhs in
            let lhsDays = countryDays[lhs.element, default: []].count
            let rhsDays = countryDays[rhs.element, default: []].count
            return lhsDays != rhsDays ? lhsDays > rhsDays : lhs.offset < rhs.offset
        }.map(\.element)

        guard let startDay = days.first, let endDay = days.last, let mainCountryCode = countryCodes.first else {
            return nil
        }
        return Trip(startDay: startDay, endDay: endDay, dayCount: DayKey.daysBetween(startDay, endDay) + 1,
                    countryCodes: countryCodes, mainCountryCode: mainCountryCode, cityIds: cityIds,
                    isOngoing: endDay == today)
    }
}
