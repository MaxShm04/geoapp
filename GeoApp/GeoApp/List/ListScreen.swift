import SwiftData
import SwiftUI

/// Alle Länder und Städte als Liste, umschaltbar, sortiert nach letztem Besuch oder alphabetisch.
/// Einträge lassen sich per Wischen löschen.
struct ListScreen: View {
    enum Kind: String, CaseIterable, Identifiable {
        case countries = "Länder"
        case cities = "Städte"
        var id: Self { self }
    }

    enum Order: String, CaseIterable, Identifiable {
        case lastVisit = "Zuletzt besucht"
        case alphabetical = "Alphabetisch"
        var id: Self { self }
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
                    ContentUnavailableView("Noch keine Orte", systemImage: "mappin.slash",
                                           description: Text("Sobald die App einen Ort erfasst, erscheint er hier."))
                } else {
                    List {
                        Picker("Ansicht", selection: $kind) {
                            ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
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
            .navigationTitle("Orte")
            .toolbar {
                Menu {
                    Picker("Sortierung", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Sortierung", systemImage: "arrow.up.arrow.down")
                }
                .disabled(countries.isEmpty)
            }
            .navigationDestination(for: String.self) { code in
                CountryDetail(code: code)
                    .navigationTitle(CountryNames.name(for: code))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .alert(
                countryToDelete.map { "\(CountryNames.name(for: $0.isoCode)) löschen?" } ?? "",
                isPresented: Binding(get: { countryToDelete != nil }, set: { if !$0 { countryToDelete = nil } })
            ) {
                Button("Löschen", role: .destructive) {
                    if let code = countryToDelete?.isoCode { try? Deletion.deleteCountry(code, context: context) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle Besuche in diesem Land und seine Städte werden entfernt.")
            }
            .alert(
                cityToDelete.map { "\($0.name) löschen?" } ?? "",
                isPresented: Binding(get: { cityToDelete != nil }, set: { if !$0 { cityToDelete = nil } })
            ) {
                Button("Löschen", role: .destructive) {
                    if let id = cityToDelete?.geonamesId { try? Deletion.deleteCity(id, context: context) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle Besuche in dieser Stadt werden entfernt.")
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
                    Button("Löschen", systemImage: "trash", role: .destructive) { countryToDelete = country }
                }
            }
        } footer: {
            Text("Zum Löschen nach links wischen.")
        }
    }

    private func cityCount(in code: String) -> String {
        let count = cities.filter { $0.countryCode == code }.count
        return count == 1 ? "1 Stadt" : "\(count) Städte"
    }

    // MARK: Städte

    private var sortedCities: [City] {
        switch order {
        case .lastVisit:
            cities.sorted { $0.lastVisited > $1.lastVisited }
        case .alphabetical:
            cities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private var cityRows: some View {
        Section {
            ForEach(sortedCities) { city in
                VisitRow(title: city.name, subtitle: CountryNames.name(for: city.countryCode),
                         first: city.firstVisited, last: city.lastVisited)
                    .swipeActions {
                        Button("Löschen", systemImage: "trash", role: .destructive) { cityToDelete = city }
                    }
            }
        } footer: {
            Text("Zum Löschen nach links wischen.")
        }
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
                    Button("Alle Regionen") { selectedRegion = nil }
                }
            }
    }
}
