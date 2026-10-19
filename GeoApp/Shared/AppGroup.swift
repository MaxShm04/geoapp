import Foundation

/// Gemeinsamer Speicherort von App und Widgets (App Group, Entscheidung D7).
nonisolated enum AppGroup {
    static let identifier = "group.de.max.geoapp"

    /// Ordner der App Group, `nil` ohne Berechtigung (etwa wenn die Entitlements fehlen).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
