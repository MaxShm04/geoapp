import GeoCore
import MapLibre
import SwiftUI

/// Weltkarte als eigene, ruhige Zeichnung mit MapLibre: einfarbiges Meer, graue Länder, besuchte
/// Länder im Akzentton, keine Beschriftung, keine Kacheln, kein Netzwerk.
///
/// Drei Ebenen:
/// - Welt: Länder eingefärbt.
/// - Land: Regionen nach Besuchstagen abgestuft, wichtige Städte mit Namen.
/// - Region: Kreise nach Besuchstagen abgestuft, alle Städte mit Namen.
///
/// Wechsel per Tipp (mit Kamerafahrt) oder durch Zoomen: Füllt ein besuchtes Land oder eine
/// besuchte Region einen Großteil des Bildschirms, geht die Karte von selbst eine Ebene tiefer,
/// beim Herauszoomen wieder zurück.
struct WorldMapView: UIViewRepresentable {
    let visitedCodes: Set<String>
    let focus: CountryFocus?
    let selectedRegion: String?
    /// Platz unten, den das Blatt mit der Liste belegt.
    let bottomInset: CGFloat
    let onSelectCountry: (String?) -> Void
    let onSelectRegion: (String?) -> Void
    let onFocusFinished: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: MapStyle.emptyStyleURL(dark: context.environment.colorScheme == .dark))
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.compassView.compassVisibility = .hidden
        map.allowsRotating = false
        map.allowsTilting = false
        map.minimumZoomLevel = 0.5
        map.maximumZoomLevel = 11
        map.setCenter(CLLocationCoordinate2D(latitude: 35, longitude: 15), zoomLevel: 1.2, animated: false)
        map.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        for doubleTap in map.gestureRecognizers?.compactMap({ $0 as? UITapGestureRecognizer }) ?? []
        where doubleTap.numberOfTapsRequired == 2 {
            tap.require(toFail: doubleTap)
        }
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, @MainActor MLNMapViewDelegate {
        var parent: WorldMapView

        private struct Shown: Equatable {
            var visited: Set<String>
            var focusCode: String?
            var regionDays: [String: Int]
            var districtDays: [String: Int]
            var selectedRegion: String?
            var scheme: ColorScheme
        }

        private var style: MLNStyle?
        /// Großstädte, deren OSM-Details schon auf der Karte liegen.
        private var shownCityDetails: Set<Int> = []
        private var shown: Shown?
        private var shownPins: [CityPin] = []
        /// Kamera vor dem ersten Hineinzoomen per Tipp, dorthin geht es beim Schließen zurück.
        private var cameraBeforeFocus: MLNMapCamera?
        private var awaitingFocus = false
        /// Die Auswahl kam vom Zoomen: Die Kamera bleibt, wo der Finger sie hingebracht hat.
        private var selectionFromZoom = false

        init(parent: WorldMapView) {
            self.parent = parent
        }

        // MARK: Stil und Ebenen

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.style = style
            MapStyle.install(in: style)
            MapDetailLayers.install(in: style)
            shown = nil
            shownCityDetails = []
            update(mapView)
        }

        // MARK: Zustand abgleichen

        func update(_ map: MLNMapView) {
            guard let style else { return }
            let focus = parent.focus
            let next = Shown(visited: parent.visitedCodes, focusCode: focus?.code,
                             regionDays: focus?.regionDays ?? [:], districtDays: focus?.districtDays ?? [:],
                             selectedRegion: parent.selectedRegion, scheme: parent.colorScheme)
            let previous = shown
            guard next != previous else {
                if !awaitingFocus, focus != nil, visiblePins != shownPins { showPins(on: map) }
                return
            }
            shown = next
            if next.scheme != previous?.scheme {
                MapStyle.applyColors(in: style, scheme: next.scheme)
                MapDetailLayers.applyColors(in: style, scheme: next.scheme)
            }
            updateShapes(in: style)

            let fromZoom = selectionFromZoom
            selectionFromZoom = false
            if next.focusCode != previous?.focusCode {
                if let code = next.focusCode {
                    if fromZoom {
                        showPins(on: map)
                        parent.onFocusFinished()
                    } else {
                        if previous?.focusCode == nil { cameraBeforeFocus = map.camera }
                        fly(map, to: MapShapes.bounds(forCountry: code, cities: coordinates(of: focus?.pins ?? [])))
                    }
                } else {
                    removePins(from: map)
                    if !fromZoom { flyBack(map) }
                }
            } else if next.selectedRegion != previous?.selectedRegion, let code = next.focusCode {
                if fromZoom {
                    showPins(on: map)
                } else if let id = next.selectedRegion, let region = RegionIndex.shared.region(id: id) {
                    fly(map, to: MapShapes.bounds(for: region, cities: coordinates(of: visiblePins)))
                } else {
                    fly(map, to: MapShapes.bounds(forCountry: code, cities: coordinates(of: focus?.pins ?? [])))
                }
            } else if !awaitingFocus {
                showPins(on: map)
            }
        }

        /// Städte, die gerade zu sehen sein sollen: in der Region nur deren Städte, sonst alle des Landes.
        private var visiblePins: [CityPin] {
            guard let focus = parent.focus else { return [] }
            guard let region = parent.selectedRegion else { return focus.pins }
            return focus.pins.filter { $0.regionId == region }
        }

        private func coordinates(of pins: [CityPin]) -> [CLLocationCoordinate2D] {
            pins.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }

        /// Setzt die Flächen von Ländern, Regionen und Kreisen mit ihrem jeweiligen Stil.
        private func updateShapes(in style: MLNStyle) {
            let focus = parent.focus
            let focused = focus != nil
            let selectedRegion = parent.selectedRegion

            // Hat das gewählte Land Regionen, liegt es neutral darunter, damit nichts durchscheint.
            let hasRegions = focus.map { !RegionIndex.shared.regions(in: $0.code).isEmpty } ?? false
            var countries: [MLNMultiPolygonFeature] = []
            for (code, feature) in MapShapes.countries {
                let kind = code == focus?.code ? (hasRegions ? "base" : "selected")
                    : parent.visitedCodes.contains(code) ? "visited" : "unvisited"
                feature.attributes = ["style": focused && kind != "selected" && kind != "base" ? "\(kind)-dim" : kind]
                countries.append(feature)
            }
            MapStyle.setShapes(countries, source: MapStyle.countries, in: style)

            let districtsOfRegion = focus.flatMap { focus in
                selectedRegion.map { DistrictIndex.shared.districts(inRegion: $0, countryCode: focus.code) }
            } ?? []

            var regions: [MLNMultiPolygonFeature] = []
            if let focus {
                for region in RegionIndex.shared.regions(in: focus.code) {
                    let level = CountryFocus.level(forDays: focus.regionDays[region.id] ?? 0)
                    let kind: String
                    if selectedRegion == region.id {
                        // Mit Kreisen darüber neutral und ohne Linie, sonst schaut die Region an den
                        // Rändern der (aus anderer Quelle stammenden) Kreise heraus.
                        kind = districtsOfRegion.isEmpty ? "r\(level)" : "focus"
                    } else {
                        kind = selectedRegion == nil ? "r\(level)" : "r\(level)-dim"
                    }
                    let feature = MapShapes.feature(for: region)
                    feature.attributes = ["style": kind]
                    regions.append(feature)
                }
            }
            MapStyle.setShapes(regions, source: MapStyle.regions, in: style)

            var districts: [MLNMultiPolygonFeature] = []
            if let focus {
                for district in districtsOfRegion {
                    let feature = MapShapes.feature(for: district)
                    feature.attributes = ["style": "d\(CountryFocus.level(forDays: focus.districtDays[district.id] ?? 0))"]
                    districts.append(feature)
                }
            }
            MapStyle.setShapes(districts, source: MapStyle.districts, in: style)
        }

        // MARK: Kamera

        private func padding(for map: MLNMapView) -> UIEdgeInsets {
            UIEdgeInsets(top: map.safeAreaInsets.top + 44, left: 8, bottom: parent.bottomInset + 4, right: 8)
        }

        private func fly(_ map: MLNMapView, to bounds: BoundingBox?) {
            removePins(from: map)
            guard let bounds else { return }
            awaitingFocus = true
            let padding = padding(for: map)
            let camera = map.cameraThatFitsCoordinateBounds(bounds.coordinateBounds, edgePadding: padding)
            // Längere, weichere Kamerafahrt als die Standardanimation. Der Rand gilt auch beim Setzen,
            // sonst sitzt das Land mittig hinter dem Blatt.
            map.setCamera(camera, withDuration: 0.9, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                          edgePadding: padding) { [weak self, weak map] in
                guard let self, let map, self.awaitingFocus else { return }
                self.awaitingFocus = false
                self.showPins(on: map)
                self.parent.onFocusFinished()
            }
        }

        private func flyBack(_ map: MLNMapView) {
            awaitingFocus = false
            let camera = cameraBeforeFocus ?? MLNMapCamera(lookingAtCenter: map.centerCoordinate,
                                                           altitude: map.camera.altitude * 6, pitch: 0, heading: 0)
            cameraBeforeFocus = nil
            map.setCamera(camera, withDuration: 0.9, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
        }

        // MARK: Ebenen durch Zoomen wechseln

        /// Eine Ebene tiefer, wenn das Land oder die Region mindestens so viel Breite füllt.
        private static let enterRatio = 1.6
        /// Wieder eine Ebene höher, wenn der Ausschnitt so viel breiter ist (Abstand gegen Flackern).
        private static let leaveRatio = 3.2

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            layoutLabels(on: mapView)
            if let style { MapDetailLayers.update(in: style, map: mapView, shown: &shownCityDetails) }
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom]
            guard !reason.isDisjoint(with: gestures), !awaitingFocus else { return }
            switchLevelForZoom(mapView)
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            layoutLabels(on: mapView)
        }

        private func switchLevelForZoom(_ map: MLNMapView) {
            let visible = map.visibleCoordinateBounds
            var visibleWidth = visible.ne.longitude - visible.sw.longitude
            if visibleWidth <= 0 { visibleWidth += 360 }
            let center = map.centerCoordinate
            let centerCountry = GeoLookup.shared.countryCode(latitude: center.latitude, longitude: center.longitude)

            func fills(_ bounds: BoundingBox?) -> Bool {
                guard let bounds else { return false }
                return visibleWidth <= bounds.width * Self.enterRatio
            }
            func lost(_ bounds: BoundingBox?) -> Bool {
                guard let bounds else { return true }
                return visibleWidth >= bounds.width * Self.leaveRatio || !bounds.intersects(visible)
            }
            func visitedRegion(at coordinate: CLLocationCoordinate2D, in focus: CountryFocus) -> Region? {
                guard let region = RegionIndex.shared.region(in: focus.code, lat: coordinate.latitude, lon: coordinate.longitude),
                      (focus.regionDays[region.id] ?? 0) > 0 else { return nil }
                return region
            }

            guard let focus = parent.focus else {
                // Welt: in ein besuchtes Land hineingezoomt?
                if let code = centerCountry, parent.visitedCodes.contains(code),
                   fills(MapShapes.bounds(forCountry: code, cities: [])) {
                    selectionFromZoom = true
                    parent.onSelectCountry(code)
                }
                return
            }

            let countryBounds = MapShapes.bounds(forCountry: focus.code, cities: [])
            if let regionId = parent.selectedRegion {
                let regionBounds = RegionIndex.shared.region(id: regionId).flatMap { MapShapes.bounds(for: $0, cities: []) }
                let neighbour = centerCountry == focus.code ? visitedRegion(at: center, in: focus) : nil
                if let neighbour, neighbour.id != regionId, fills(MapShapes.bounds(for: neighbour, cities: [])) {
                    // In eine besuchte Nachbarregion geschoben.
                    selectionFromZoom = true
                    parent.onSelectRegion(neighbour.id)
                } else if lost(regionBounds) {
                    // Aus der Region herausgezoomt: zurück zum Land oder ganz zur Welt.
                    selectionFromZoom = true
                    if lost(countryBounds) { parent.onSelectCountry(nil) } else { parent.onSelectRegion(nil) }
                }
                return
            }

            // Land: in eine besuchte Region hineingezoomt?
            if centerCountry == focus.code, let region = visitedRegion(at: center, in: focus),
               fills(MapShapes.bounds(for: region, cities: [])) {
                selectionFromZoom = true
                parent.onSelectRegion(region.id)
                return
            }
            // In ein anderes besuchtes Land geschoben oder weit herausgezoomt.
            if let code = centerCountry, code != focus.code, parent.visitedCodes.contains(code),
               fills(MapShapes.bounds(forCountry: code, cities: [])) {
                selectionFromZoom = true
                parent.onSelectCountry(code)
            } else if lost(countryBounds) {
                selectionFromZoom = true
                parent.onSelectCountry(nil)
            }
        }

        // MARK: Städtepunkte

        private func showPins(on map: MLNMapView) {
            removePins(from: map)
            shownPins = visiblePins
            map.addAnnotations(shownPins.map(CityAnnotation.init))
        }

        private func removePins(from map: MLNMapView) {
            let cities = (map.annotations ?? []).filter { $0 is CityAnnotation }
            map.removeAnnotations(cities)
            shownPins = []
        }

        /// Wie viel auf einmal zu sehen ist, je nach Ebene und Zoom.
        private struct Density {
            /// Kleine Städte (unter 50.000 Einwohnern, kurzer Aufenthalt) zeigen?
            var smallCities: Bool
            /// Namen auch für kleine Städte?
            var smallLabels: Bool
            /// Höchstzahl an Namen.
            var maxLabels: Int
            /// Mindestabstand zwischen zwei Punkten in Bildschirmpunkten.
            var minDotSpacing: CGFloat
        }

        /// Stufenlos nach Zoom: Ein Land im Ganzen (Zoom ~5) zeigt etwa 12 Namen wichtiger Städte,
        /// jede Zoomstufe mehr lässt mehr Namen und kleinere Orte zu. In der Region kommen die
        /// kleinen Orte sofort dazu.
        private func density(on map: MLNMapView) -> Density {
            let zoom = map.zoomLevel
            let inRegion = parent.selectedRegion != nil
            let maxLabels = Int(min(max(12 + (zoom - 5) * 8, 10), 40)) + (inRegion ? 6 : 0)
            return Density(smallCities: inRegion || zoom >= 6,
                           smallLabels: inRegion || zoom >= 6.5,
                           maxLabels: maxLabels,
                           minDotSpacing: zoom >= 7 ? 10 : 14)
        }

        /// Verteilt Punkte und Namen nach Wichtigkeit, damit es ruhig bleibt:
        /// - Punkte, die einem wichtigeren zu nahe kommen, werden ausgeblendet.
        /// - Ein Name erscheint an der ersten freien Stelle (unter, über, rechts oder links vom
        ///   Punkt), die keinen anderen Namen oder Punkt verdeckt, bis zur Höchstzahl.
        /// - Angetippte Städte zeigen ihren Punkt und Namen immer.
        private func layoutLabels(on map: MLNMapView) {
            let density = density(on: map)
            let entries = (map.annotations ?? []).compactMap { annotation -> (pin: CityPin, view: CityDotView, point: CGPoint)? in
                guard let city = annotation as? CityAnnotation, let view = map.view(for: city) as? CityDotView else { return nil }
                return (city.pin, view, map.convert(city.coordinate, toPointTo: map))
            }
            .sorted { ($0.view.isSelected ? 1 : 0, $0.pin.importance) > ($1.view.isSelected ? 1 : 0, $1.pin.importance) }

            // Punkte
            var shownDots: [(id: Int, point: CGPoint)] = []
            var visible: [(pin: CityPin, view: CityDotView, point: CGPoint)] = []
            for entry in entries {
                let allowed = entry.view.isSelected || entry.pin.isProminent || density.smallCities
                let crowded = shownDots.contains { hypot($0.point.x - entry.point.x, $0.point.y - entry.point.y) < density.minDotSpacing }
                let show = entry.view.isSelected || (allowed && !crowded)
                entry.view.setDotVisible(show)
                if show {
                    shownDots.append((entry.pin.id, entry.point))
                    visible.append(entry)
                } else {
                    entry.view.setLabelPosition(nil)
                }
            }

            // Namen
            let dotRects = shownDots.map { ($0.id, CGRect(x: $0.point.x - 5, y: $0.point.y - 5, width: 10, height: 10)) }
            var placed: [CGRect] = []
            for entry in visible {
                let wanted = entry.view.isSelected
                    || (placed.count < density.maxLabels && (entry.pin.isProminent || density.smallLabels))
                guard wanted else {
                    entry.view.setLabelPosition(nil)
                    continue
                }
                let free = CityDotView.LabelPosition.allCases.first { position in
                    let rect = entry.view.labelFrame(at: entry.point, position: position).insetBy(dx: -3, dy: -1)
                    return !placed.contains { $0.intersects(rect) }
                        && !dotRects.contains { $0.0 != entry.pin.id && $0.1.intersects(rect) }
                }
                let position = free ?? (entry.view.isSelected ? .below : nil)
                entry.view.setLabelPosition(position)
                if let position { placed.append(entry.view.labelFrame(at: entry.point, position: position)) }
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let city = annotation as? CityAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: CityDotView.reuseID) as? CityDotView
                ?? CityDotView(reuseIdentifier: CityDotView.reuseID)
            view.configure(pin: city.pin)
            return view
        }

        func mapView(_ mapView: MLNMapView, didAdd annotationViews: [MLNAnnotationView]) {
            layoutLabels(on: mapView)
            for (index, view) in annotationViews.enumerated() {
                view.alpha = 0
                UIView.animate(withDuration: 0.35, delay: min(Double(index) * 0.02, 0.4), options: [.curveEaseOut]) {
                    view.alpha = 1
                }
            }
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { false }

        /// Tipp auf einen kleinen Punkt zeigt seinen Namen.
        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            layoutLabels(on: mapView)
        }

        func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {
            layoutLabels(on: mapView)
        }

        // MARK: Tippen

        /// Welt: Tipp auf ein besuchtes Land zoomt hinein.
        /// Land: Tipp auf eine besuchte Region zoomt in die Region, Tipp aufs Meer zurück zur Welt.
        /// Die Tipp-Koordinate ist ein Kartenpunkt, kein Standort, und wird nicht gespeichert.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: map)
            if map.hitTest(point, with: nil)?.firstSuperview(of: MLNAnnotationView.self) != nil { return }

            let coordinate = map.convert(point, toCoordinateFrom: map)
            let code = GeoLookup.shared.countryCode(latitude: coordinate.latitude, longitude: coordinate.longitude)

            if let focus = parent.focus, code == focus.code {
                let region = RegionIndex.shared.region(in: focus.code, lat: coordinate.latitude, lon: coordinate.longitude)
                if let region, (focus.regionDays[region.id] ?? 0) > 0 {
                    if region.id != parent.selectedRegion { parent.onSelectRegion(region.id) }
                } else if parent.selectedRegion != nil {
                    parent.onSelectRegion(nil)
                }
            } else if let code, parent.visitedCodes.contains(code) {
                if code != parent.focus?.code { parent.onSelectCountry(code) }
            } else if parent.focus != nil {
                parent.onSelectCountry(nil)
            }
        }
    }
}

// MARK: - Stil

/// Leerer MapLibre-Stil ohne Kacheln und Schriften, dazu unsere Quellen und Ebenen.
enum MapStyle {
    static let countries = "countries"
    static let regions = "regions"
    static let districts = "districts"

    /// Minimaler Stil, nur der Hintergrund (das Meer). Wird lokal geschrieben, nichts wird geladen.
    /// Das Meer hat gleich die passende Farbe, sonst blitzt die Karte im Dunkelmodus hell auf.
    static func emptyStyleURL(dark: Bool) -> URL {
        dark ? darkStyleURL : lightStyleURL
    }

    private static let lightStyleURL = writeStyle(name: "light", ocean: "#EDF2F5")
    private static let darkStyleURL = writeStyle(name: "dark", ocean: "#141719")

    private static func writeStyle(name: String, ocean: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geoapp-style-\(name).json")
        let json = #"{"version":8,"name":"GeoApp","sources":{},"layers":[{"id":"ocean","type":"background","paint":{"background-color":"\#(ocean)"}}]}"#
        try? json.data(using: .utf8)?.write(to: url)
        return url
    }

    static func install(in style: MLNStyle) {
        for id in [countries, regions, districts] {
            let source = MLNShapeSource(identifier: id, shape: nil, options: nil)
            style.addSource(source)
            let fill = MLNFillStyleLayer(identifier: "\(id)-fill", source: source)
            fill.fillAntialiased = NSExpression(forConstantValue: true)
            style.addLayer(fill)
            let line = MLNLineStyleLayer(identifier: "\(id)-line", source: source)
            line.lineJoin = NSExpression(forConstantValue: "round")
            line.lineWidth = lineWidth(for: id)
            style.addLayer(line)
        }
    }

    static func setShapes(_ features: [MLNMultiPolygonFeature], source id: String, in style: MLNStyle) {
        (style.source(withIdentifier: id) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: features)
    }

    /// Grenzen dünn, solange viel Welt zu sehen ist, und kräftiger beim Hineinzoomen.
    private static func lineWidth(for id: String) -> NSExpression {
        let stops: [Double: Double] = switch id {
        case countries: [0: 0.15, 2: 0.3, 4: 0.7, 7: 1.2]
        case regions: [3: 0.5, 5: 0.9, 8: 1.4]
        default: [5: 0.3, 7: 0.6, 9: 1.0]
        }
        return NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                            stops: NSExpression(forConstantValue: stops))
    }

    static func applyColors(in style: MLNStyle, scheme: ColorScheme) {
        let dark = scheme == .dark
        let accent = UIColor(named: "AccentColor")!.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let land = dark ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.84, alpha: 1)
        let ocean = dark ? UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1) : UIColor(red: 0.93, green: 0.95, blue: 0.96, alpha: 1)
        let border = dark ? UIColor(white: 0.17, alpha: 1) : UIColor.white
        let levels: [CGFloat] = [0, 0.45, 0.7, 0.95]

        (style.layer(withIdentifier: "ocean") as? MLNBackgroundStyleLayer)?.backgroundColor = NSExpression(forConstantValue: ocean)

        let countryColors: [String: UIColor] = [
            "unvisited": land, "visited": accent.withAlphaComponent(0.85), "selected": accent.withAlphaComponent(0.9),
            "unvisited-dim": land.withAlphaComponent(0.55), "visited-dim": accent.withAlphaComponent(0.35),
            "base": land,
        ]
        var regionColors: [String: UIColor] = [:]
        var districtColors: [String: UIColor] = [:]
        for level in 0...3 {
            let color = level == 0 ? land : accent.withAlphaComponent(levels[level])
            regionColors["r\(level)"] = color
            regionColors["r\(level)-dim"] = level == 0 ? land.withAlphaComponent(0.6) : accent.withAlphaComponent(levels[level] * 0.4)
            regionColors["focus"] = land
            districtColors["d\(level)"] = color
        }

        for (id, colors) in [(countries, countryColors), (regions, regionColors), (districts, districtColors)] {
            let cases = Dictionary(uniqueKeysWithValues: colors.map {
                (NSExpression(forConstantValue: $0.key), NSExpression(forConstantValue: $0.value))
            })
            (style.layer(withIdentifier: "\(id)-fill") as? MLNFillStyleLayer)?.fillColor =
                NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "style"), in: cases, default: NSExpression(forConstantValue: land))
            let line = style.layer(withIdentifier: "\(id)-line") as? MLNLineStyleLayer
            line?.lineColor = NSExpression(forConstantValue: border)
            // Nur die aktive Ebene zeichnet kräftige Linien. Die Ebenen stammen aus verschiedenen
            // Quellen, ihre Grenzen liegen an den Rändern leicht versetzt. Gröbere Ebenen werden
            // deshalb im Fokus nur angedeutet, unter einer feineren Ebene gar nicht gezeichnet.
            var opacities: [String: Double] = ["base": 0, "focus": 0]
            for key in colors.keys where key.hasSuffix("-dim") { opacities[key] = 0.3 }
            line?.lineOpacity = NSExpression(
                forMLNMatchingKey: NSExpression(forKeyPath: "style"),
                in: Dictionary(uniqueKeysWithValues: opacities.map {
                    (NSExpression(forConstantValue: $0.key), NSExpression(forConstantValue: $0.value))
                }),
                default: NSExpression(forConstantValue: 1))
        }
    }
}

// MARK: - Stadtpunkt

final class CityAnnotation: NSObject, MLNAnnotation {
    let pin: CityPin
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude) }

    init(pin: CityPin) {
        self.pin = pin
    }
}

/// Stadtpunkt: wichtige Städte größer, kleinere als feiner Punkt. Der Name hängt außerhalb des
/// Rahmens am Punkt, seine Position verteilt `layoutLabels`.
final class CityDotView: MLNAnnotationView {
    static let reuseID = "CityDot"

    enum LabelPosition: CaseIterable {
        case below, above, right, left
    }

    private let dot = UIView()
    private let label = UILabel()
    private var dotSize: CGFloat = 6
    /// Höhe des Namens, wächst mit der Schriftgröße.
    private var labelHeight: CGFloat { ceil(label.font.lineHeight) }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        clipsToBounds = false
        scalesWithViewingDistance = false
        addSubview(dot)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = .label
        // Heller Schein um die Schrift, damit Namen auf jeder Fläche lesbar bleiben.
        label.layer.shadowOffset = .zero
        label.layer.shadowRadius = 2
        label.layer.shadowOpacity = 1
        label.isHidden = true
        addSubview(label)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) {
            (view: CityDotView, _) in
            view.applyColors()
            view.label.sizeToFit()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(pin: CityPin) {
        dotSize = pin.isProminent ? 11 : 6
        frame = CGRect(x: frame.minX, y: frame.minY, width: dotSize, height: dotSize)
        dot.frame = bounds
        dot.layer.cornerRadius = dotSize / 2
        dot.layer.borderWidth = pin.isProminent ? 1.5 : 1
        // Dunkler Punkt mit hellem Rand, damit er auf jeder Fläche sichtbar ist.
        dot.backgroundColor = UIColor.label.withAlphaComponent(pin.isProminent ? 0.85 : 0.6)
        applyColors()
        label.text = pin.name
        label.sizeToFit()
        label.frame = labelFrame(for: .below)
        label.isHidden = true
        dot.alpha = 0
    }

    /// Rand und Schein sind CGColors und folgen dem Hell- und Dunkelmodus nicht von selbst.
    private func applyColors() {
        let background = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
        dot.layer.borderColor = background
        label.layer.shadowColor = background
    }

    /// Wo der Name auf der Karte läge, wenn der Punkt bei `point` sitzt.
    func labelFrame(at point: CGPoint, position: LabelPosition) -> CGRect {
        labelFrame(for: position).offsetBy(dx: point.x - dotSize / 2, dy: point.y - dotSize / 2)
    }

    /// Position des Namens relativ zum Punkt (Ursprung oben links am Punkt).
    private func labelFrame(for position: LabelPosition) -> CGRect {
        let width = label.bounds.width, height = labelHeight
        return switch position {
        case .below: CGRect(x: (dotSize - width) / 2, y: dotSize + 1, width: width, height: height)
        case .above: CGRect(x: (dotSize - width) / 2, y: -height - 1, width: width, height: height)
        case .right: CGRect(x: dotSize + 3, y: (dotSize - height) / 2, width: width, height: height)
        case .left: CGRect(x: -width - 3, y: (dotSize - height) / 2, width: width, height: height)
        }
    }

    /// Punkt ein- oder ausblenden, sanft.
    func setDotVisible(_ visible: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        // Ausgeblendete Punkte fangen keine Tipps ab, damit der Tipp die Region darunter erreicht.
        isUserInteractionEnabled = visible
        guard dot.alpha != alpha else { return }
        UIView.animate(withDuration: 0.2) { self.dot.alpha = alpha }
    }

    /// Name an einer Position zeigen oder (bei `nil`) ausblenden.
    func setLabelPosition(_ position: LabelPosition?) {
        if let position { label.frame = labelFrame(for: position) }
        let visible = position != nil
        guard label.isHidden == visible else { return }
        UIView.transition(with: label, duration: 0.2, options: .transitionCrossDissolve) {
            self.label.isHidden = !visible
        }
    }
}

private extension UIView {
    func firstSuperview<T: UIView>(of type: T.Type) -> T? {
        var view: UIView? = self
        while let current = view {
            if let match = current as? T { return match }
            view = current.superview
        }
        return nil
    }
}
