import Foundation
import GeoCore
import SwiftData

// Datenschutz: Kein Modell enthält die Position der Person. Alle Werte stammen aus den
// Datensätzen (Natural Earth, GeoNames) oder dem Zeitpunkt. `GeoAppTests` prüft das.
//
// Die Modelle hier sind der aktuelle Stand (`SchemaV2` in Schema.swift). Wer ein Feld ändert,
// legt eine neue Schema-Version mit Migrationsstufe an, sonst lässt sich der Speicher nicht öffnen.

/// Ein besuchtes Land. Färbt die Weltkarte ein.
@Model
final class Country {
    @Attribute(.unique) var isoCode: String
    /// Englischer Name aus Natural Earth. Angezeigt wird der Name in der Gerätesprache (`CountryNames`).
    var name: String
    var firstVisited: Date
    var lastVisited: Date

    init(isoCode: String, name: String, visited: Date) {
        self.isoCode = isoCode
        self.name = name
        self.firstVisited = visited
        self.lastVisited = visited
    }
}

/// Eine besuchte Stadt. Punkte in der Länderansicht.
@Model
final class City {
    @Attribute(.unique) var geonamesId: Int
    var name: String
    var countryCode: String
    /// Stadtmitte laut GeoNames, nicht die Position der Person.
    var centerLatitude: Double
    var centerLongitude: Double
    var firstVisited: Date
    var lastVisited: Date

    init(from city: GeoCore.City, visited: Date) {
        self.geonamesId = city.id
        self.name = city.name
        self.countryCode = city.countryCode
        self.centerLatitude = city.latitude
        self.centerLongitude = city.longitude
        self.firstVisited = visited
        self.lastVisited = visited
    }
}

/// Ein Ort an einem Tag. Weitere Erfassungen am selben Tag und Ort erhöhen nur den Zähler
/// (Regel 4), so bleibt der Speicher klein, auch wenn iOS die App oft weckt.
///
/// Ort heißt: Stadt (oder nur Land, wenn keine Stadt im Radius liegt) und Kreis, ohne Kreis die
/// Region. Alles Gebiete aus den Datensätzen, keine Koordinaten.
@Model
final class DayVisit {
    /// Tag, Ort und Herkunft in einem Schlüssel, siehe `DayVisits.Entry.key`.
    @Attribute(.unique) var key: String
    /// Tag als yyyymmdd in der Zeitzone zum Zeitpunkt der Erfassung.
    var day: Int
    var countryCode: String
    /// Ohne Stadt im Radius zählt nur das Land, dann ist die ID leer.
    var geonamesId: Int?
    /// Region und Kreis an der erfassten Position (nicht an der Stadtmitte).
    var regionId: String?
    var districtId: String?
    var firstSeen: Date
    var lastSeen: Date
    /// Wie oft der Ort an diesem Tag erfasst wurde.
    var captureCount: Int
    /// Ein Bit je `CaptureSource`, siehe `CaptureSource.bit`.
    var sourceMask: Int
    /// Testdaten aus den Einstellungen, getrennt von echten Besuchen.
    var isDemo: Bool

    init(key: String, day: Int, countryCode: String, geonamesId: Int?, regionId: String?, districtId: String?,
         firstSeen: Date, lastSeen: Date, captureCount: Int, sourceMask: Int, isDemo: Bool) {
        self.key = key
        self.day = day
        self.countryCode = countryCode
        self.geonamesId = geonamesId
        self.regionId = regionId
        self.districtId = districtId
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.captureCount = captureCount
        self.sourceMask = sourceMask
        self.isDemo = isDemo
    }

    var sources: [CaptureSource] { CaptureSource.allCases.filter { sourceMask & $0.bit != 0 } }
}

/// Eintrag im Diagnose-Log: Zeitpunkt, Quelle, Ergebnis, gefundene Stadt und Entfernung zur Stadtmitte.
@Model
final class DiagnosticEntry {
    var timestamp: Date
    var sourceRaw: String
    var outcome: String
    var cityName: String?
    var districtName: String?
    var countryCode: String?
    var distanceToCityCenterKm: Double?
    /// "Genaue Position" war aus: iOS liefert dann absichtlich eine ungefähre Position.
    var reducedAccuracy: Bool = false

    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .manual }

    init(timestamp: Date, source: CaptureSource, outcome: String,
         cityName: String? = nil, districtName: String? = nil, countryCode: String? = nil,
         distanceToCityCenterKm: Double? = nil, reducedAccuracy: Bool = false) {
        self.timestamp = timestamp
        self.sourceRaw = source.rawValue
        self.outcome = outcome
        self.cityName = cityName
        self.districtName = districtName
        self.countryCode = countryCode
        self.distanceToCityCenterKm = distanceToCityCenterKm
        self.reducedAccuracy = reducedAccuracy
    }
}

extension CaptureSource {
    var label: String {
        switch self {
        case .significantChange: String(localized: "Location change")
        case .visit: String(localized: "Visit")
        case .manual: String(localized: "On open")
        case .demo: String(localized: "Test data")
        }
    }

    /// Fester Wert je Quelle für `DayVisit.sourceMask`. Nie umnummerieren, die Werte sind gespeichert.
    nonisolated var bit: Int {
        switch self {
        case .significantChange: 1
        case .visit: 2
        case .manual: 4
        case .demo: 8
        }
    }
}
