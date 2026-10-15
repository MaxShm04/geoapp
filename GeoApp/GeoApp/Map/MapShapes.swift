import CoreLocation
import GeoCore
import MapLibre

/// Wandelt Länder-, Regions- und Kreisgrenzen aus GeoCore in MapLibre-Formen um und berechnet
/// die Ausschnitte für die Kamera. Gebaute Formen bleiben im Speicher.
enum MapShapes {
    /// Ein Land als Fläche, Attribut `style` wird je nach Zustand gesetzt.
    static let countries: [String: MLNMultiPolygonFeature] = {
        var result: [String: MLNMultiPolygonFeature] = [:]
        for country in GeoLookup.shared.countries.countries {
            let feature = MLNMultiPolygonFeature(polygons: country.polygons.compactMap(polygon))
            feature.identifier = country.code
            result[country.code] = feature
        }
        return result
    }()

    private static var regionCache: [String: MLNMultiPolygonFeature] = [:]
    private static var districtCache: [String: MLNMultiPolygonFeature] = [:]

    static func feature(for region: Region) -> MLNMultiPolygonFeature {
        if let cached = regionCache[region.id] { return cached }
        let feature = MLNMultiPolygonFeature(polygons: region.polygons.compactMap(polygon))
        feature.identifier = region.id
        regionCache[region.id] = feature
        return feature
    }

    static func feature(for district: District) -> MLNMultiPolygonFeature {
        if let cached = districtCache[district.id] { return cached }
        let feature = MLNMultiPolygonFeature(polygons: district.polygons.compactMap(polygon))
        feature.identifier = district.id
        districtCache[district.id] = feature
        return feature
    }

    nonisolated static func polygon(_ polygon: GeoCore.Polygon) -> MLNPolygon? {
        let rings = polygon.rings.map { flat in
            stride(from: 0, to: flat.count - 1, by: 2).map {
                CLLocationCoordinate2D(latitude: flat[$0 + 1], longitude: flat[$0])
            }
        }
        guard let outer = rings.first, outer.count >= 3 else { return nil }
        let holes = rings.dropFirst().filter { $0.count >= 3 }.map { MLNPolygon(coordinates: $0, count: UInt($0.count)) }
        return MLNPolygon(coordinates: outer, count: UInt(outer.count), interiorPolygons: holes)
    }

    // MARK: Ausschnitte

    /// Ausschnitt für ein Land: das größte Teilgebiet (bei Frankreich das Mutterland, nicht die
    /// Überseegebiete) plus die besuchten Städte, solange das nicht um die halbe Welt reicht.
    static func bounds(forCountry code: String, cities: [CLLocationCoordinate2D]) -> BoundingBox? {
        guard let country = GeoLookup.shared.countries.shape(for: code) else { return nil }
        return focusBounds(country.polygons, cities: cities)
    }

    static func bounds(for region: Region, cities: [CLLocationCoordinate2D]) -> BoundingBox? {
        focusBounds(region.polygons, cities: cities)
    }

    private static func focusBounds(_ polygons: [GeoCore.Polygon], cities: [CLLocationCoordinate2D]) -> BoundingBox? {
        guard var box = polygons.max(by: { $0.bbox.area < $1.bbox.area })?.bbox else { return nil }
        for city in cities {
            let extended = BoundingBox(minLat: min(box.minLat, city.latitude), minLon: min(box.minLon, city.longitude),
                                       maxLat: max(box.maxLat, city.latitude), maxLon: max(box.maxLon, city.longitude))
            if extended.maxLon - extended.minLon < 180 { box = extended }
        }
        // Mindestgröße, damit Kleinstaaten wie Monaco nicht bildschirmfüllend werden.
        let minSide = 0.3
        let padLat = max((minSide - (box.maxLat - box.minLat)) / 2, 0)
        let padLon = max((minSide - (box.maxLon - box.minLon)) / 2, 0)
        return BoundingBox(minLat: box.minLat - padLat, minLon: box.minLon - padLon,
                           maxLat: box.maxLat + padLat, maxLon: box.maxLon + padLon)
    }
}

extension BoundingBox {
    var width: Double { maxLon - minLon }

    var coordinateBounds: MLNCoordinateBounds {
        MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
    }

    func intersects(_ bounds: MLNCoordinateBounds) -> Bool {
        minLat <= bounds.ne.latitude && maxLat >= bounds.sw.latitude
            && minLon <= bounds.ne.longitude && maxLon >= bounds.sw.longitude
    }
}
