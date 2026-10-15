import GeoCore
import SwiftData
import SwiftUI

/// Startbildschirm: Zähler oben, Weltkarte darunter. Ein Tipp auf ein besuchtes Land zoomt
/// in die Länderansicht mit Regionen, ein Tipp auf eine Region zeigt alle Städte dort.
struct MapScreen: View {
    @Query private var countries: [Country]
    @Query private var cities: [City]
    @Query private var visits: [DayVisit]
    @Environment(LocationService.self) private var location
    @AppStorage(AppSettings.trackingEnabled) private var trackingEnabled = true
    @State private var selectedCountry: String?
    @State private var selectedRegion: String?
    @State private var showsSheet = false

    /// Höhe des Blatts in der kleinsten Stufe. Die Karte lässt darüber Platz für das Land.
    private static let sheetHeight: CGFloat = 220

    var body: some View {
        let focus = selectedCountry.map { CountryFocus.make(code: $0, cities: cities, visits: visits) }
        NavigationStack {
            WorldMapView(
                visitedCodes: Set(countries.map(\.isoCode)),
                focus: focus,
                selectedRegion: selectedRegion,
                bottomInset: Self.sheetHeight,
                onSelectCountry: selectCountry,
                onSelectRegion: selectRegion,
                onFocusFinished: { if selectedCountry != nil { showsSheet = true } }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if selectedCountry == nil {
                    VStack(spacing: 8) {
                        counter
                        hint
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if selectedCountry != nil {
                    backButton.transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(selectedCountry == nil ? .visible : .hidden, for: .tabBar)
            .sheet(isPresented: $showsSheet, onDismiss: { selectCountry(nil) }) {
                if let focus {
                    CountrySheet(focus: focus, selectedRegion: selectedRegion, onSelectRegion: selectRegion)
                        .presentationDetents([.height(Self.sheetHeight), .medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .presentationDragIndicator(.visible)
                }
            }
            .task {
                // Regionen vorab laden, damit der erste Tipp auf ein Land nicht stockt.
                _ = await Task.detached(priority: .utility) { RegionIndex.shared.regions(in: "DE").count }.value
            }
        }
    }

    private func selectCountry(_ code: String?) {
        withAnimation(.easeInOut(duration: 0.35)) {
            selectedRegion = nil
            selectedCountry = code
        }
        if code == nil { showsSheet = false }
    }

    private func selectRegion(_ id: String?) {
        withAnimation(.easeInOut(duration: 0.35)) { selectedRegion = id }
    }

    private var counter: some View {
        Text(Self.counterText(countries: countries.count, cities: cities.count))
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }

    /// Leise Hinweise unter dem Zähler: Erfassung läuft nicht im Hintergrund, oder noch nichts erfasst.
    @ViewBuilder private var hint: some View {
        if !trackingEnabled {
            hintCapsule("Erfassung ist ausgeschaltet", systemImage: "pause.circle")
        } else if location.authorization != .authorizedAlways {
            Button(action: openSettings) {
                hintCapsule("Standort „Immer“ erlauben", systemImage: "location.slash")
            }
            .buttonStyle(.plain)
        } else if countries.isEmpty {
            hintCapsule("Die Karte füllt sich, sobald du unterwegs bist.", systemImage: nil)
        }
    }

    private func hintCapsule(_ text: String, systemImage: String?) -> some View {
        Group {
            if let systemImage { Label(text, systemImage: systemImage) } else { Text(text) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    /// In der Region zurück zum Land, im Land zurück zur Welt.
    private var backButton: some View {
        Button {
            if selectedRegion != nil { selectRegion(nil) } else { selectCountry(nil) }
        } label: {
            Image(systemName: selectedRegion != nil ? "chevron.left" : "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedRegion != nil ? "Zurück zum Land" : "Zurück zur Weltkarte")
        .padding(.leading, 16)
        .padding(.top, 4)
    }

    static func counterText(countries: Int, cities: Int) -> String {
        let countryWord = countries == 1 ? "Land" : "Länder"
        let cityWord = cities == 1 ? "Stadt" : "Städte"
        return "\(countries) \(countryWord) · \(cities) \(cityWord)"
    }
}
