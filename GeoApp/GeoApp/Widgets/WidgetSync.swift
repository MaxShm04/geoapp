import Foundation
import GeoCore
import OSLog
import SwiftData
import WidgetKit

/// Schreibt die Daten für die Widgets in die App Group und lädt sie neu (Entscheidung D8):
/// nach einem neuen Ort, beim Wechsel in den Hintergrund, nach Löschen und Testdaten.
enum WidgetSync {
    private static let log = Logger(subsystem: "de.max.geoapp", category: "Widgets")
    /// Größe der Kartenbilder in Pixeln, reicht für das mittlere Widget mit 3-facher Auflösung.
    static let mapSize = CGSize(width: 1080, height: 510)
    /// Besuchte Länder, für die die Kartenbilder zuletzt gezeichnet wurden.
    private static var renderedCountries: Set<String>?

    static func refresh(context: ModelContext, now: Date = .now) {
        // Speicher nur im Arbeitsspeicher (Tests, Notfall nach einem Fehler) schreiben nichts für die Widgets.
        guard let directory = AppGroup.containerURL,
              context.container.configurations.allSatisfy({ !$0.isStoredInMemoryOnly }) else { return }
        do {
            let visits = try context.fetch(FetchDescriptor<DayVisit>())
            let days = visits.map(PlaceDay.init)
            let snapshot = WidgetSnapshot.make(days: days, today: DayKey.today(now: now), cityName: cityName, now: now)
            try snapshot.write(to: WidgetSnapshot.url(in: directory))
            let visited = Set(visits.map(\.countryCode))
            if visited != renderedCountries {
                try writeMaps(visited: visited, to: directory)
                renderedCountries = visited
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            log.error("Widget-Daten schreiben fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func writeMaps(visited: Set<String>, to directory: URL) throws {
        for (dark, name) in [(false, WidgetSnapshot.mapLightFileName), (true, WidgetSnapshot.mapDarkFileName)] {
            guard let data = WidgetMapRenderer.render(visited: visited, size: mapSize, dark: dark) else { continue }
            try data.write(to: directory.appending(path: name), options: .atomic)
        }
    }

    private static func cityName(_ id: Int) -> String {
        PlaceNames.city(id: id, fallback: GeoLookup.shared.cities.city(id: id)?.name ?? "")
    }
}
