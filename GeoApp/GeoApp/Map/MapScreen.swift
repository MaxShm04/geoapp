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
    @AppStorage("mapYear") private var yearStorage = "all"
    @Environment(ProStore.self) private var store
    @State private var selectedCountry: String?
    @State private var selectedRegion: String?
    @State private var showsSheet = false

    /// Höhe des Blatts in der kleinsten Stufe. Die Karte lässt darüber Platz für das Land.
    private static let sheetHeight: CGFloat = 220

    var body: some View {
        let focus = selectedCountry.map { CountryFocus.make(code: $0, cities: shownCities, visits: shownVisits) }
        NavigationStack {
            WorldMapView(
                visitedCodes: shownCountryCodes,
                focus: focus,
                selectedRegion: selectedRegion,
                bottomInset: Self.sheetHeight,
                onSelectCountry: selectCountry,
                onSelectRegion: selectRegion,
                onFocusFinished: { if selectedCountry != nil { showsSheet = true } }
            )
            .ignoresSafeArea()
            // Ohne gewähltes Land ersetzt ein Element mit Zusammenfassung die Karte für VoiceOver.
            // Mit gewähltem Land bleibt die Standardbedienung. Ein Modifier mit Bedingung auf der Karte
            // selbst ginge nicht, `accessibilityLabel` nimmt kein optionales Text.
            .accessibilityHidden(selectedCountry == nil)
            .overlay {
                if selectedCountry == nil {
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel(Self.accessibilitySummary(countries: shownCountryCodes.count, cities: shownCities.count))
                        .accessibilityHint("Tap a highlighted country to see its regions and cities.")
                }
            }
            .overlay(alignment: .top) {
                if selectedCountry == nil {
                    VStack(spacing: 8) {
                        counterRow
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

    /// Zähler und Jahresfilter nebeneinander.
    private var counterRow: some View {
        HStack(spacing: 8) {
            counter
            YearMenu(selection: yearSelection,
                     years: YearFilter.availableYears(days: visits.map(\.day), currentYear: currentYear),
                     currentYear: currentYear,
                     isPro: store.isPro)
        }
        .padding(.top, 8)
    }

    private var counter: some View {
        Text(Self.counterText(countries: shownCountryCodes.count, cities: shownCities.count))
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
    }

    /// Jahr, das die Karte zeigt. Ohne Pro gilt wieder "All years", etwa nach Ende des Abos.
    private var yearFilter: YearFilter {
        let filter = YearFilter(storageValue: yearStorage) ?? .all
        return ProGate.allows(.yearFilter, year: filter, currentYear: currentYear, isPro: store.isPro) ? filter : .all
    }

    private var currentYear: Int {
        DayKey.year(DayKey.today())
    }

    /// Auswahl im Menü zeigt den wirksamen Filter, sonst stünde nach Ende des Abos ein gesperrtes Jahr dort.
    private var yearSelection: Binding<String> {
        Binding(get: { yearFilter.storageValue }, set: { yearStorage = $0 })
    }

    /// Besuche im gewählten Jahr. Bei "All years" alle.
    private var shownVisits: [DayVisit] {
        visits.filter { yearFilter.contains(day: $0.day) }
    }

    /// Besuchte Länder. Bei "All years" wie bisher aus der Länderliste.
    private var shownCountryCodes: Set<String> {
        yearFilter == .all ? Set(countries.map(\.isoCode)) : Set(shownVisits.map(\.countryCode))
    }

    /// Städte mit Besuchen im gewählten Jahr. Bei "All years" alle.
    private var shownCities: [City] {
        guard yearFilter != .all else { return cities }
        let ids = Set(shownVisits.compactMap(\.geonamesId))
        return cities.filter { ids.contains($0.geonamesId) }
    }

    /// Leise Hinweise unter dem Zähler: Erfassung läuft nicht im Hintergrund, oder noch nichts erfasst.
    @ViewBuilder private var hint: some View {
        if yearFilter != .all, shownVisits.isEmpty, !countries.isEmpty {
            hintCapsule("No places recorded in this year yet.", systemImage: nil)
        } else if !trackingEnabled {
            hintCapsule("Recording is turned off", systemImage: "pause.circle")
        } else if location.authorization != .authorizedAlways {
            Button(action: openSettings) {
                hintCapsule("Allow location “Always”", systemImage: "location.slash")
            }
            .buttonStyle(.plain)
        } else if countries.isEmpty {
            hintCapsule("The map fills in as you travel.", systemImage: nil)
        }
    }

    private func hintCapsule(_ text: LocalizedStringKey, systemImage: String?) -> some View {
        Group {
            if let systemImage { Label(text, systemImage: systemImage) } else { Text(text) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
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
        .accessibilityLabel(backLabel)
        .padding(.leading, 16)
        .padding(.top, 4)
    }

    /// VoiceOver-Name des Zurück-Knopfs: im Land zurück zur Weltkarte, in der Region zurück zum Land.
    private var backLabel: LocalizedStringKey {
        selectedRegion != nil ? "Back to country" : "Back to world map"
    }

    static func counterText(countries: Int, cities: Int, locale: Locale = .current) -> String {
        L10n.string("\(countries) countries", locale: locale) + " · " + L10n.string("\(cities) cities", locale: locale)
    }

    /// VoiceOver-Zusammenfassung der Weltkarte, etwa "World map. 5 countries and 12 cities visited. …".
    static func accessibilitySummary(countries: Int, cities: Int, locale: Locale = .current) -> String {
        let countriesText = L10n.string("\(countries) countries", locale: locale)
        let citiesText = L10n.string("\(cities) cities", locale: locale)
        return L10n.string("World map. \(countriesText) and \(citiesText) visited. The list tab shows them as a list.",
                           locale: locale)
    }
}
