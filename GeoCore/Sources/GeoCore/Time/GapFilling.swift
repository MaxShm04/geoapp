import Foundation

/// Schließt Tageslücken: Ein Tag ohne Erfassung zählt dort, wo die Person zuletzt gesehen wurde.
public enum GapFilling {
    /// Längere Lücken bleiben leer (Telefon aus, App nicht aktiv).
    public static let maxGapDays = 30

    /// Die Einträge plus ergänzte Tage (`isInferred`), sortiert nach Tag. `today` begrenzt die
    /// Lücke nach der letzten Erfassung.
    public static func fill(_ days: [PlaceDay], through today: Int) -> [PlaceDay] {
        let byDay = Dictionary(grouping: days) { $0.day }
        let capturedDays = byDay.keys.sorted()
        var inferred: [PlaceDay] = []

        for (index, day) in capturedDays.enumerated() {
            guard let source = lastSeen(in: byDay[day] ?? []) else { continue }
            // Lücke bis zum nächsten erfassten Tag, nach dem letzten Tag bis heute.
            let missing: Int
            if index + 1 < capturedDays.count {
                missing = DayKey.daysBetween(day, capturedDays[index + 1]) - 1
            } else {
                missing = DayKey.daysBetween(day, today)
            }
            guard (1...maxGapDays).contains(missing) else { continue }
            inferred += (1...missing).map { offset in
                PlaceDay(day: DayKey.adding(offset, to: day), countryCode: source.countryCode,
                         cityId: source.cityId, regionId: source.regionId,
                         lastSeen: source.lastSeen, isInferred: true)
            }
        }

        return (days + inferred).enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map { $0.element }
    }

    /// Der Eintrag mit der letzten Erfassung. Bei Gleichstand gewinnt der spätere in der Eingabe.
    private static func lastSeen(in entries: [PlaceDay]) -> PlaceDay? {
        var latest: PlaceDay?
        for entry in entries {
            if let current = latest, entry.lastSeen < current.lastSeen { continue }
            latest = entry
        }
        return latest
    }
}
