import SwiftData
import SwiftUI

/// Alle Länder und Städte als Liste, als Blatt über die Karte. Umschaltbar, sortiert nach letztem Besuch
/// oder alphabetisch, durchsuchbar nach Namen in der Gerätesprache. Ein Eintrag öffnet die Ortsansicht,
/// dort lässt er sich auch löschen.
struct PlacesList: View {
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

    @Query private var countries: [Country]
    @Query private var cities: [City]
    @AppStorage("listKind") private var kind: Kind = .countries
    @AppStorage("listOrder") private var order: Order = .lastVisit
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

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
                    .searchable(text: $search)
                    .overlay {
                        if isSearchEmpty { ContentUnavailableView.search(text: search) }
                    }
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $order) {
                            ForEach(Order.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(countries.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: PlaceRef.self) { place in
                PlaceDetailView(place: place)
            }
        }
    }

    private var isSearchEmpty: Bool {
        guard !search.isEmpty else { return false }
        switch kind {
        case .countries: return shownCountries.isEmpty
        case .cities: return shownCities.isEmpty
        }
    }

    /// Treffer im Namen, ohne Rücksicht auf Groß- und Kleinschreibung und Akzente.
    static func matches(_ search: String, _ names: String...) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || names.contains { $0.localizedStandardContains(query) }
    }

    // MARK: Länder

    private var shownCountries: [Country] {
        let named = countries.map { (country: $0, name: CountryNames.name(for: $0.isoCode)) }
            .filter { Self.matches(search, $0.name) }
        switch order {
        case .lastVisit:
            return named.map(\.country).sorted { $0.lastVisited > $1.lastVisited }
        case .alphabetical:
            return named.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.country)
        }
    }

    private var countryRows: some View {
        Section {
            ForEach(shownCountries) { country in
                NavigationLink(value: PlaceRef.country(country.isoCode)) {
                    VisitRow(title: CountryNames.name(for: country.isoCode),
                             subtitle: cityCount(in: country.isoCode),
                             first: country.firstVisited, last: country.lastVisited)
                }
            }
        }
    }

    private func cityCount(in code: String) -> String {
        Self.cityCountText(cities.filter { $0.countryCode == code }.count)
    }

    // MARK: Städte

    /// Städte passen auch über ihr Land, etwa „Italien“ für alle italienischen Städte.
    private var shownCities: [City] {
        let named = cities.map { (city: $0, name: PlaceNames.city($0)) }
            .filter { Self.matches(search, $0.name, CountryNames.name(for: $0.city.countryCode)) }
        switch order {
        case .lastVisit:
            return named.map(\.city).sorted { $0.lastVisited > $1.lastVisited }
        case .alphabetical:
            return named.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.city)
        }
    }

    private var cityRows: some View {
        Section {
            ForEach(shownCities) { city in
                NavigationLink(value: PlaceRef.city(city.geonamesId)) {
                    VisitRow(title: PlaceNames.city(city), subtitle: CountryNames.name(for: city.countryCode),
                             first: city.firstVisited, last: city.lastVisited)
                }
            }
        }
    }

    static func cityCountText(_ count: Int, locale: Locale = .current) -> String {
        L10n.string("\(count) cities", locale: locale)
    }
}
