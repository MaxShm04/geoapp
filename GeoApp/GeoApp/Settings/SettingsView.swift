import CoreLocation
import GeoCore
import SwiftUI

struct SettingsView: View {
    @Environment(LocationService.self) private var location
    @AppStorage(AppSettings.trackingEnabled) private var trackingEnabled = true
    @AppStorage(AppSettings.visitsEnabled) private var visitsEnabled = true
    @AppStorage(AppSettings.diagnosticsEnabled) private var diagnosticsEnabled = false
    @Environment(\.modelContext) private var context
    @State private var confirmsDeleteAll = false
    @AppStorage(AppSettings.mockDataEnabled) private var mockDataEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Berechtigung", value: location.authorization.label)
                    if location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse {
                        LabeledContent("Genaue Position", value: location.hasReducedAccuracy ? "Aus" : "An")
                    }
                    if location.authorization != .authorizedAlways || location.hasReducedAccuracy {
                        Button("In iOS-Einstellungen ändern", action: openSettings)
                    }
                } header: {
                    Text("Standort")
                } footer: {
                    if location.authorization != .authorizedAlways {
                        Text("Für die Erfassung im Hintergrund braucht die App die Berechtigung Immer.")
                    } else if location.hasReducedAccuracy {
                        Text("Ohne genaue Position verschiebt iOS den Standort um einige Kilometer. Städte können dann danebenliegen, an Grenzen auch das Land.")
                    }
                }

                Section {
                    LabeledContent("Status", value: location.isMonitoring ? "Läuft" : "Aus")
                    Toggle("Orte erfassen", isOn: $trackingEnabled)
                    Toggle("Aufenthalte (Visits)", isOn: $visitsEnabled)
                        .disabled(!trackingEnabled)
                } header: {
                    Text("Erfassung")
                } footer: {
                    Text("Die App erfasst bei größeren Ortswechseln. Aufenthalte sind ein zweiter Weg, den iOS meldet, wenn du länger an einem Ort bleibst. Beide speichern nur Stadt, Land und Zeitpunkt.")
                }
                .onChange(of: trackingEnabled) { location.applyTrackingSettings() }
                .onChange(of: visitsEnabled) { location.applyTrackingSettings() }

                Section {
                    Toggle("Diagnose-Log", isOn: $diagnosticsEnabled)
                    NavigationLink("Log ansehen") { DiagnosticLogView() }
                } header: {
                    Text("Diagnose")
                } footer: {
                    Text("Hält fest, wann die App geweckt wurde, welche Stadt sie gefunden hat und wie weit es zur Stadtmitte war. Ohne Koordinaten.")
                }

                #if DEBUG
                Section {
                    Toggle("Testdaten in Bayern", isOn: $mockDataEnabled)
                } header: {
                    Text("Testdaten")
                } footer: {
                    Text("Fügt Beispielreisen in Bayern hinzu, von 12 Tagen in München bis zu kurzen Stopps in Kleinstädten, um Karte und Regionen auszuprobieren. Ausschalten entfernt genau diese Einträge wieder, echte Besuche bleiben.")
                }
                .onChange(of: mockDataEnabled) { _, enabled in
                    if enabled { MockData.enable(context: context) } else { MockData.disable(context: context) }
                }
                #endif

                Section {
                    Button("Aktuellen Ort zuordnen") { location.probeCurrentLocation() }
                        .disabled(location.probe == .running)
                    if let probe = location.probe {
                        ProbeResultRow(result: probe)
                    }
                } header: {
                    Text("Zuordnung prüfen")
                } footer: {
                    Text("Ordnet deinen Standort einmal offline einer Stadt und einem Land zu. Nichts davon wird gespeichert.")
                }

                Section {
                    Button("Alle Daten löschen", role: .destructive) { confirmsDeleteAll = true }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Einzelne Länder und Städte löschst du in der Liste per Wischen.")
                }

                Section {
                    NavigationLink("Lizenzen") { LicensesView() }
                    LabeledContent("Version", value: Self.version)
                }
            }
            .tint(.accentColor)
            .navigationTitle("Einstellungen")
            .alert("Alle Daten löschen?", isPresented: $confirmsDeleteAll) {
                Button("Alles löschen", role: .destructive) {
                    try? Deletion.deleteAll(context: context)
                    mockDataEnabled = false
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle Länder, Städte, Besuchstage und das Diagnose-Log werden unwiderruflich entfernt.")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

private struct ProbeResultRow: View {
    let result: LocationService.ProbeResult

    var body: some View {
        switch result {
        case .running:
            HStack {
                ProgressView()
                Text("Suche Standort …").foregroundStyle(.secondary)
            }
        case .match(let match):
            VStack(alignment: .leading, spacing: 4) {
                Text(match.city?.name ?? "Keine Stadt im Umkreis von \(Int(GeoLookup.cityRadiusKm)) km")
                    .font(.headline)
                Text(CountryNames.name(for: match.countryCode))
                if let km = match.distanceToCityCenterKm {
                    Text("\(km.formatted(.number.precision(.fractionLength(1)))) km zur Stadtmitte")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .noCountry:
            Text("Kein Land gefunden, zum Beispiel auf offenem Meer.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Standort nicht verfügbar: \(message)")
                .foregroundStyle(.secondary)
        }
    }
}
