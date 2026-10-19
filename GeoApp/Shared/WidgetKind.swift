import Foundation

/// Die Widgets. Nur der Zähler ist ohne Pro nutzbar (Entscheidung D9).
nonisolated enum WidgetKind: String, CaseIterable, Sendable {
    case counter, newPlaces, map

    /// Das Widget ohne Pro.
    static let free: WidgetKind = .counter

    /// `kind` für WidgetKit und `WidgetCenter.reloadTimelines(ofKind:)`.
    var kind: String {
        switch self {
        case .counter: "Counter"
        case .newPlaces: "NewPlaces"
        case .map: "Map"
        }
    }
}
