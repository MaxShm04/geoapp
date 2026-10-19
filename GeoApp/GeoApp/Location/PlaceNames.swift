import Foundation
import GeoCore

/// Namen von Städten und Regionen in der Gerätesprache. Angezeigt wird der Name zur ID, gespeichert
/// bleibt der Name zum Zeitpunkt des Besuchs als Rückfall (Entscheidung D3).
enum PlaceNames {
    /// Sprache, in der die App Ländernamen zeigt, damit Stadt-, Regions- und Ländernamen zusammenpassen.
    static var language: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Stadtname in der Gerätesprache, sonst `fallback` (der gespeicherte Name).
    static func city(id: Int, fallback: String) -> String {
        GeoLookup.shared.cities.localizedName(id: id, language: language) ?? fallback
    }

    /// Stadtname für eine gespeicherte Stadt.
    static func city(_ city: City) -> String {
        self.city(id: city.geonamesId, fallback: city.name)
    }

    /// Regionsname in der Gerätesprache, sonst `fallback`.
    static func region(id: String, fallback: String) -> String {
        RegionIndex.shared.region(id: id).map { region($0) } ?? fallback
    }

    /// Regionsname in der Gerätesprache für eine geladene Region.
    static func region(_ region: Region) -> String {
        region.localizedName(language: language)
    }
}
