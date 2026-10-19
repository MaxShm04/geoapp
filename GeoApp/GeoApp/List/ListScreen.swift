import SwiftData
import SwiftUI

/// Alle Länder und Städte als Liste, umschaltbar, sortiert nach letztem Besuch oder alphabetisch.
/// Einträge lassen sich per Wischen löschen.
struct ListScreen: View {
    enum Kind: String, CaseIterable, Identifiable {
        case countries
        case cities
        var id: Self { self }
        var title: LocalizedStringResource {
            switch self {
            case .countries: "Countries"
            case .cities: "Cities"
            }
        }
    }

    enum Order: String, CaseIterable, Identifiable {
        case lastVisit
        case alphabetical
        var id: Self { self }
        var title: LocalizedStringResource {
            switch self {
            case .lastVisit: "Last visited"
            case .alphabetical: "Alphabetical"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query private var countries: [Country]
    @Query private var cities: [City]
    @AppStorage("listKind") private var kind: Kind = .countries
    @AppStorage("listOrder") private var order: Order = .lastVisit
    @State private var countryToDelete: Country?
    @State private var cityToDelete: City?

    var body: some View {
        NavigationStack {
            Group {
                if countries.isEmpty {
                    ContentUnavailableView("No places yet", systemImage: "mappin.slash",
                                           description: Text("A place appears here as soon as the app records it."))
                } else {
                    List {
                        Picker("View", selection: $kind) {
                            ForEach(Kind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        switch kind {
                        case .countries: countryRows
                        case .cities: cityRows
                        }
                    }
                }
            }
            .navigationTitle("Places")
            .toolbar {
                Menu {
                    Picker("Sort", selection: $order) {
                        ForEach(Order.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .disabled(countries.isEmpty)
            }
            .navigationDestination(for: String.self) { code in
                CountryDetail(code: code)
                    .navigationTitle(CountryNames.name(for: code))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .alert(
                countryToDelete.map { String(localized: "Delete \(CountryNames.name(for: $0.isoCode))?") } ?? "",
                isPresented: Binding(get: { countryToDelete != nil }, set: { if !$0 { countryToDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let code = countryToDelete?.isoCode { try? Deletion.deleteCountry(code, context: context) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All visits in this country and its cities will be removed.")
            }
            .alert(
                cityToDelete.map { String(localized: "Delete \(PlaceNames.city($0))?") } ?? "",
                isPresented: Binding(get: { cityToDelete != nil }, set: { if !$0 { cityToDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let id = cityToDelete?.geonamesId { try? Deletion.deleteCity(id, context: context) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All visits in this city will be removed.")
            }
        }
    }

    // MARK: Länder

    private var sortedCountries: [Country] {
        switch order {
        case .lastVisit:
            countries.sorted { $0.lastVisited > $1.lastVisited }
        case .alphabetical:
            countries.sorted {
                CountryNames.name(for: $0.isoCode).localizedStandardCompare(CountryNames.name(for: $1.isoCode)) == .orderedAscending
            }
        }
    }

    private var countryRows: some View {
        Section {
            ForEach(sortedCountries) { country in
                NavigationLink(value: country.isoCode) {
                    VisitRow(title: CountryNames.name(for: country.isoCode),
                             subtitle: cityCount(in: country.isoCode),
                             first: country.firstVisited, last: country.lastVisited)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { countryToDelete = country }
                }
            }
        } footer: {
            Text("Swipe left to delete.")
        }
    }

    private func cityCount(in code: String) -> String {
        Self.cityCountText(cities.filter { $0.countryCode == code }.count)
    }

    // MARK: Städte

    private var sortedCities: [City] {
        switch order {
        case .lastVisit:
            cities.sorted { $0.lastVisited > $1.lastVisited }
        case .alphabetical:
            cities.map { (city: $0, name: PlaceNames.city($0)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { $0.city }
        }
    }

    private var cityRows: some View {
        Section {
            ForEach(sortedCities) { city in
                VisitRow(title: PlaceNames.city(city), subtitle: CountryNames.name(for: city.countryCode),
                         first: city.firstVisited, last: city.lastVisited)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { cityToDelete = city }
                    }
            }
        } footer: {
            Text("Swipe left to delete.")
        }
    }

    static func cityCountText(_ count: Int, locale: Locale = .current) -> String {
        L10n.string("\(count) cities", locale: locale)
    }
}

/// Länderseite aus der Liste: dieselbe Übersicht wie im Blatt der Karte, mit Regionen zum Aufklappen.
private struct CountryDetail: View {
    let code: String

    @Query private var cities: [City]
    @Query private var visits: [DayVisit]
    @State private var selectedRegion: String?

    var body: some View {
        CountrySheet(focus: CountryFocus.make(code: code, cities: cities, visits: visits),
                     selectedRegion: selectedRegion) { selectedRegion = $0 }
            .toolbar {
                if selectedRegion != nil {
                    Button("All regions") { selectedRegion = nil }
                }
            }
    }
}
