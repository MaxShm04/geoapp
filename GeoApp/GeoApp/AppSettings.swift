import Foundation

/// Schlüssel für die Einstellungen in UserDefaults, gemeinsam genutzt von Views (`@AppStorage`)
/// und Diensten.
enum AppSettings {
    static let onboardingDone = "onboardingDone"
    static let alwaysRequested = "alwaysRequested"
    static let trackingEnabled = "trackingEnabled"
    static let visitsEnabled = "visitsEnabled"
    static let diagnosticsEnabled = "diagnosticsEnabled"
    static let mockDataEnabled = "mockDataEnabled"
    /// Datenstand (`GeoLookup.dataVersion`), für den die gespeicherten Städte zuletzt angeglichen wurden.
    static let dataVersion = "dataVersion"
    /// Heimatgebiet aus den Einstellungen (`PlaceDay.areaKey`), leer = automatisch erkannt (Phase 2, D4).
    static let homeRegionOverride = "homeRegionOverride"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            onboardingDone: false,
            alwaysRequested: false,
            trackingEnabled: true,
            visitsEnabled: true,
            diagnosticsEnabled: false,
            mockDataEnabled: false,
        ])
    }
}
