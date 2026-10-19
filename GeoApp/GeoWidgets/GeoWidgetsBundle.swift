import SwiftUI
import WidgetKit

/// Die drei Widgets der Erweiterung. Nur der Zähler ist ohne Pro (Entscheidung D9).
@main
struct GeoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        NewPlacesWidget()
        MapWidget()
    }
}
