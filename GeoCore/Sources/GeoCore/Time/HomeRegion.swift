import Foundation

/// Heimatregion: das Gebiet mit den meisten Tagen in den letzten 90 Tagen.
public enum HomeRegion {
    public static let windowDays = 90

    /// `areaKey` des Heimatgebiets oder `nil` ohne Daten. `days` sind bereits lückenlos (`GapFilling`).
    public static func detect(_ days: [PlaceDay], today: Int) -> String? {
        guard let latest = days.map({ $0.day }).max() else { return nil }
        // Ohne Daten im Fenster gilt das Fenster, das am letzten Tag mit Daten endet.
        let reference = days.contains { inWindow($0.day, ending: today) } ? today : latest

        var daysByArea: [String: Set<Int>] = [:]
        for place in days where inWindow(place.day, ending: reference) {
            daysByArea[place.areaKey, default: []].insert(place.day)
        }
        // Meiste Tage, dann der jüngere letzte Tag, dann der kleinere Schlüssel.
        return daysByArea
            .map { (key: $0.key, count: $0.value.count, last: $0.value.max() ?? 0) }
            .min { a, b in
                if a.count != b.count { return a.count > b.count }
                if a.last != b.last { return a.last > b.last }
                return a.key < b.key
            }?
            .key
    }

    /// Liegt `day` in den `windowDays` Tagen, die mit `reference` enden?
    private static func inWindow(_ day: Int, ending reference: Int) -> Bool {
        (0..<windowDays).contains(DayKey.daysBetween(day, reference))
    }
}
