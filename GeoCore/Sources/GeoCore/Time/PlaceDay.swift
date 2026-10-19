import Foundation

/// Ein Ort an einem Tag als Wert, ohne SwiftData. Die App bildet ihn aus `DayVisit`.
/// Enthält nur IDs aus den Datensätzen und den Zeitpunkt, nie Koordinaten.
public struct PlaceDay: Sendable, Hashable {
    /// yyyymmdd
    public var day: Int
    public var countryCode: String
    public var cityId: Int?
    public var regionId: String?
    /// Letzte Erfassung an diesem Ort und Tag.
    public var lastSeen: Date
    /// Durch das Schließen von Lücken ergänzt, nicht erfasst.
    public var isInferred: Bool

    public init(day: Int, countryCode: String, cityId: Int? = nil, regionId: String? = nil,
                lastSeen: Date = .distantPast, isInferred: Bool = false) {
        self.day = day
        self.countryCode = countryCode
        self.cityId = cityId
        self.regionId = regionId
        self.lastSeen = lastSeen
        self.isInferred = isInferred
    }

    /// Gebiet für Heimatregion und Reisen: die Region, ohne Region das Land.
    public var areaKey: String {
        regionId ?? countryCode
    }
}
