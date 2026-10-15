import GeoCore
import MapLibre
import SwiftUI

/// Zusätzliche Kartenebene über den Flächen von Ländern, Regionen und Kreisen: für Großstädte ab
/// Zoom 8 die Hauptstraßen (OpenStreetMap). Seen und Flüsse zeigt die Karte bewusst nicht.
enum MapDetailLayers {
    private static let roads = "roads"

    /// Ab diesem Zoom erscheinen die Straßen der Großstädte.
    static let cityDetailMinZoom = 8.0

    static func install(in style: MLNStyle) {
        let roadSource = MLNShapeSource(identifier: roads, shape: nil, options: nil)
        style.addSource(roadSource)

        let roadLine = MLNLineStyleLayer(identifier: "\(roads)-line", source: roadSource)
        roadLine.minimumZoomLevel = Float(cityDetailMinZoom)
        roadLine.lineCap = NSExpression(forConstantValue: "round")
        roadLine.lineJoin = NSExpression(forConstantValue: "round")
        // Zoom muss außen stehen, die Straßenklasse wählt innen die Breite.
        func widths(_ motorway: Double, _ trunk: Double, _ primary: Double) -> NSExpression {
            NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "c"),
                         in: [NSExpression(forConstantValue: 0): NSExpression(forConstantValue: motorway),
                              NSExpression(forConstantValue: 1): NSExpression(forConstantValue: trunk)],
                         default: NSExpression(forConstantValue: primary))
        }
        roadLine.lineWidth = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                          stops: NSExpression(forConstantValue: [8: widths(1.0, 0.7, 0.4), 11: widths(2.4, 1.8, 1.2)]))
        roadLine.lineOpacity = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                            stops: NSExpression(forConstantValue: [cityDetailMinZoom: 0, cityDetailMinZoom + 1: 0.75]))
        style.addLayer(roadLine)
    }

    static func applyColors(in style: MLNStyle, scheme: ColorScheme) {
        let dark = scheme == .dark
        let road = dark ? UIColor(white: 0.40, alpha: 1) : UIColor.white
        (style.layer(withIdentifier: "\(roads)-line") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: road)
    }

    // MARK: Straßen nachladen

    /// Lädt die Straßen der Großstädte, die gerade im Bild sind. Bereits geladene bleiben stehen,
    /// damit beim Verschieben nichts flackert.
    static func update(in style: MLNStyle, map: MLNMapView, shown: inout Set<Int>) {
        guard map.zoomLevel >= cityDetailMinZoom - 0.5 else { return }
        let bounds = map.visibleCoordinateBounds
        let visible = BoundingBox(minLat: bounds.sw.latitude, minLon: bounds.sw.longitude,
                                  maxLat: bounds.ne.latitude, maxLon: bounds.ne.longitude)
        let wanted = Set(CityDetailIndex.shared.cities(intersecting: visible))
        guard !wanted.isSubset(of: shown) else { return }
        shown.formUnion(wanted)

        let roadFeatures = shown.compactMap { CityDetailIndex.shared.detail(for: $0) }.flatMap(\.roads).map { road -> MLNPolylineFeature in
            let feature = polyline(road.line)
            feature.attributes = ["c": road.roadClass.rawValue]
            return feature
        }
        (style.source(withIdentifier: roads) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: roadFeatures)
    }

    // MARK: Hilfen

    private static func polyline(_ line: Polyline) -> MLNPolylineFeature {
        let flat = line.points
        let coordinates = stride(from: 0, to: flat.count - 1, by: 2).map {
            CLLocationCoordinate2D(latitude: flat[$0 + 1], longitude: flat[$0])
        }
        return MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
    }
}
