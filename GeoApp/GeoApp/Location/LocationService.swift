import CoreLocation
import GeoCore
import Observation
import UIKit

/// Kapselt den einzigen `CLLocationManager` der App: Berechtigung, Erfassung im Hintergrund
/// (Significant Location Changes und Visits), Abfrage beim Öffnen und die Probe aus den Einstellungen.
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    enum ProbeResult: Equatable {
        case running
        case match(GeoMatch)
        case noCountry
        case failed(String)
    }

    private enum OneShot {
        case probe
        case appOpen
    }

    private(set) var authorization: CLAuthorizationStatus
    /// Ist "Genaue Position" aus, liefert iOS absichtlich eine um Kilometer verschobene Position.
    private(set) var accuracy: CLAccuracyAuthorization
    /// Ergebnis von "Aktuellen Ort zuordnen". Lebt nur im Speicher, enthält keine Koordinaten.
    private(set) var probe: ProbeResult?
    /// Läuft die Erfassung über Significant Location Changes gerade?
    private(set) var isMonitoring = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pendingOneShots: Set<OneShot> = []

    override private init() {
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        // Startet die App durch einen Ortswechsel im Hintergrund neu, muss die Überwachung
        // gleich wieder eingeschaltet werden, sonst kommt das auslösende Ereignis nicht an.
        applyTrackingSettings()
    }

    // MARK: Berechtigung

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// iOS zeigt die Abfrage für "Immer" nur einmal. Danach hilft nur noch der Weg über die Einstellungen.
    func requestAlways() {
        UserDefaults.standard.set(true, forKey: AppSettings.alwaysRequested)
        manager.requestAlwaysAuthorization()
    }

    // MARK: Erfassung

    var hasReducedAccuracy: Bool {
        isAuthorized && accuracy == .reducedAccuracy
    }

    private var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    private var trackingEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.trackingEnabled)
    }

    /// Schaltet Ortswechsel und Visits passend zu Berechtigung und Einstellungen ein oder aus.
    func applyTrackingSettings() {
        let track = isAuthorized && trackingEnabled
        let visits = track && UserDefaults.standard.bool(forKey: AppSettings.visitsEnabled)
        if track {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
        if visits {
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringVisits()
        }
        isMonitoring = track
    }

    /// Einmalige Abfrage beim Öffnen der App (Quelle "manuell").
    func captureOnAppOpen() {
        guard isAuthorized, trackingEnabled else { return }
        requestOneShot(.appOpen)
    }

    func probeCurrentLocation() {
        probe = .running
        requestOneShot(.probe)
    }

    private func requestOneShot(_ kind: OneShot) {
        pendingOneShots.insert(kind)
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
    }

    private func record(latitude: Double, longitude: Double, horizontalAccuracy: Double, speed: Double,
                        timestamp: Date, source: CaptureSource) {
        guard trackingEnabled else { return }
        let reduced = hasReducedAccuracy
        if let reason = VisitRules.rejectReason(horizontalAccuracy: horizontalAccuracy, speed: speed) {
            VisitRecorder.shared.reject(reason, timestamp: timestamp, source: source, reducedAccuracy: reduced)
            return
        }
        // Im Hintergrund bleiben nur wenige Sekunden. Die Aufgabe hält die App wach, bis gespeichert ist.
        let task = BackgroundTask(name: "Erfassung")
        Task {
            // Zuordnen abseits des Hauptthreads, beim ersten Mal lädt das die Geodaten.
            let match = await Task.detached(priority: .userInitiated) {
                GeoLookup.shared.resolve(latitude: latitude, longitude: longitude)
            }.value
            let outcome = VisitRecorder.shared.record(match: match, timestamp: timestamp, source: source,
                                                      reducedAccuracy: reduced)
            // Neuer Ort an diesem Tag: Widgets bekommen die neuen Zahlen (nur Zähler und Namen, keine Position).
            if case .newDay = outcome { WidgetSync.refresh(context: Store.shared.mainContext) }
            task.end()
        }
    }
}

extension LocationService: @MainActor CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        applyTrackingSettings()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude

        let wasProbe = pendingOneShots.remove(.probe) != nil
        let wasAppOpen = pendingOneShots.remove(.appOpen) != nil
        if wasProbe {
            // Nur anzeigen, nicht speichern.
            probe = GeoLookup.shared.resolve(latitude: lat, longitude: lon).map(ProbeResult.match) ?? .noCountry
        }
        if wasAppOpen || !wasProbe {
            record(latitude: lat, longitude: lon, horizontalAccuracy: location.horizontalAccuracy,
                   speed: location.speed, timestamp: location.timestamp,
                   source: wasAppOpen ? .manual : .significantChange)
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Ankunft hat ein Datum, Abreise-Meldungen ohne bekannte Ankunft nehmen das Abreisedatum.
        let timestamp = visit.arrivalDate != .distantPast ? visit.arrivalDate
            : visit.departureDate != .distantFuture ? visit.departureDate : .now
        record(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude,
               horizontalAccuracy: visit.horizontalAccuracy, speed: -1,
               timestamp: timestamp, source: .visit)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        if pendingOneShots.remove(.probe) != nil {
            probe = .failed(message)
        }
        if pendingOneShots.remove(.appOpen) != nil {
            VisitRecorder.shared.recordFailure(message, source: .manual)
        }
    }
}

/// Bittet iOS um ein paar Sekunden Laufzeit im Hintergrund und gibt sie wieder frei.
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

extension CLAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: String(localized: "Not asked yet")
        case .restricted: String(localized: "Restricted")
        case .denied: String(localized: "Denied")
        case .authorizedWhenInUse: String(localized: "While using")
        case .authorizedAlways: String(localized: "Always")
        @unknown default: String(localized: "Unknown")
        }
    }
}
