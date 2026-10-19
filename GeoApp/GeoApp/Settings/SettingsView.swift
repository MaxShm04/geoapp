import CoreLocation
import GeoCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LocationService.self) private var location
    @Environment(ProStore.self) private var store
    @State private var showsPaywall = false
    @State private var showsManageSubscriptions = false
    @AppStorage(AppSettings.trackingEnabled) private var trackingEnabled = true
    @AppStorage(AppSettings.visitsEnabled) private var visitsEnabled = true
    @AppStorage(AppSettings.diagnosticsEnabled) private var diagnosticsEnabled = false
    @Environment(\.modelContext) private var context
    @State private var confirmsDeleteAll = false
    @AppStorage(AppSettings.mockDataEnabled) private var mockDataEnabled = false
    @Query private var visits: [DayVisit]
    @AppStorage(AppSettings.homeRegionOverride) private var homeOverride = ""

    /// Tagebuch für das Heimatgebiet in der Zeile unten.
    private var journal: Journal {
        Journal.make(visits: visits, homeOverride: homeOverride, today: DayKey.today())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: store.isPro ? String(localized: "Active") : String(localized: "Free"))
                    if store.isPro {
                        Button("Manage subscription") { showsManageSubscriptions = true }
                            .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
                    } else {
                        Button("Get Pro") { showsPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await store.restore() }
                    }
                } header: {
                    Text("Pro")
                } footer: {
                    Text("Pro is optional. Recording and the map stay free.")
                }

                Section {
                    NavigationLink {
                        HomeRegionView()
                    } label: {
                        LabeledContent("Home region", value: journal.home.map { PlaceNames.area($0) } ?? String(localized: "Not known yet"))
                    }
                } header: {
                    Text("Home")
                } footer: {
                    Text("Trips are days away from your home region.")
                }

                Section {
                    LabeledContent("Permission", value: location.authorization.label)
                    if location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse {
                        LabeledContent("Precise location", value: location.hasReducedAccuracy ? String(localized: "Off") : String(localized: "On"))
                    }
                    if location.authorization != .authorizedAlways || location.hasReducedAccuracy {
                        Button("Change in iOS Settings", action: openSettings)
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if location.authorization != .authorizedAlways {
                        Text("To record in the background, the app needs the Always permission.")
                    } else if location.hasReducedAccuracy {
                        Text("Without precise location, iOS shifts your location by a few kilometers. Cities can then be off, and at borders even the country.")
                    }
                }

                Section {
                    LabeledContent("Status", value: location.isMonitoring ? String(localized: "Running") : String(localized: "Off"))
                    Toggle("Record places", isOn: $trackingEnabled)
                    Toggle("Visits", isOn: $visitsEnabled)
                        .disabled(!trackingEnabled)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("The app records when you move a greater distance. Visits are a second way, which iOS reports when you stay in one place for a while. Both save only city, country and time.")
                }
                .onChange(of: trackingEnabled) { location.applyTrackingSettings() }
                .onChange(of: visitsEnabled) { location.applyTrackingSettings() }

                Section {
                    Toggle("Diagnostic log", isOn: $diagnosticsEnabled)
                    NavigationLink("View log") { DiagnosticLogView() }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Records when the app was woken, which city it found and how far it was to the city center. Without coordinates.")
                }

                #if DEBUG
                Section {
                    Toggle("Test data in Bavaria", isOn: $mockDataEnabled)
                } header: {
                    Text("Test data")
                } footer: {
                    Text("Adds sample trips in Bavaria, from 12 days in Munich to short stops in small towns, to try the map and regions. Turning it off removes exactly these entries again. Real visits stay.")
                }
                .onChange(of: mockDataEnabled) { _, enabled in
                    if enabled { MockData.enable(context: context) } else { MockData.disable(context: context) }
                }
                #endif

                Section {
                    Button("Match current location") { location.probeCurrentLocation() }
                        .disabled(location.probe == .running)
                    if let probe = location.probe {
                        ProbeResultRow(result: probe)
                    }
                } header: {
                    Text("Check location")
                } footer: {
                    Text("Matches your location once, offline, to a city and a country. None of this is saved.")
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmsDeleteAll = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Delete individual countries and cities by swiping in the list.")
                }

                Section {
                    NavigationLink("Licenses") { LicensesView() }
                    LabeledContent("Version", value: Self.version)
                }
            }
            .tint(.accentColor)
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .navigationTitle("Settings")
            .alert("Delete all data?", isPresented: $confirmsDeleteAll) {
                Button("Delete everything", role: .destructive) {
                    try? Deletion.deleteAll(context: context)
                    mockDataEnabled = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All countries, cities, visit days and the diagnostic log will be removed permanently.")
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
                Text("Locating …").foregroundStyle(.secondary)
            }
        case .match(let match):
            VStack(alignment: .leading, spacing: 4) {
                Text(match.city.map { PlaceNames.city(id: $0.id, fallback: $0.name) } ?? String(localized: "No city within \(Int(GeoLookup.cityRadiusKm)) km"))
                    .font(.headline)
                Text(CountryNames.name(for: match.countryCode))
                if let km = match.distanceToCityCenterKm {
                    Text("\(km.formatted(.number.precision(.fractionLength(1)))) km to city center")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .noCountry:
            Text("No country found, for example at sea.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Location unavailable: \(message)")
                .foregroundStyle(.secondary)
        }
    }
}
