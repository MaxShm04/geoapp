import Foundation

/// Was die Widgets anzeigen. Die App schreibt es in die App Group (Entscheidung D8).
/// Nur Zahlen, Namen und Zeitpunkte, nie Koordinaten.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var year: Int
    var countriesTotal: Int
    var citiesTotal: Int
    var countriesThisYear: Int
    var citiesThisYear: Int
    var newCountriesThisYear: Int
    var newCitiesThisYear: Int
    /// Neue Städte dieses Jahres in der Gerätesprache, die neueste zuerst, höchstens drei.
    var newPlaceNames: [String]
    var updated: Date

    static let fileName = "widget-snapshot.json"
    static let mapLightFileName = "widget-map-light.png"
    static let mapDarkFileName = "widget-map-dark.png"

    static let placeholder = WidgetSnapshot(year: 2026, countriesTotal: 12, citiesTotal: 48, countriesThisYear: 4,
                                            citiesThisYear: 15, newCountriesThisYear: 2, newCitiesThisYear: 9,
                                            newPlaceNames: ["Lisbon", "Porto", "Seville"],
                                            updated: Date(timeIntervalSince1970: 1_800_000_000))

    static func url(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    /// Liest den Snapshot. Fehlt die Datei oder ist sie unlesbar, gibt es `nil` (die Widgets zeigen dann den Platzhalter).
    static func load(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
