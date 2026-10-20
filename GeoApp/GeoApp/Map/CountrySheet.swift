import GeoCore
import CoreLocation
import SwiftData
import SwiftUI

/// Blatt unter der Länderansicht.
/// Im Land: Name, Zeitraum und die besuchten Regionen (in kleinen Ländern direkt die Städte).
/// In der Region: die Städte der Region.
/// Ein Tipp auf eine Stadt oder auf „Days“ im Kopf öffnet die Ortsansicht darüber.
struct CountrySheet: View {
    let focus: CountryFocus
    let selectedRegion: String?
    @Binding var place: PlaceRef?
    let onSelectRegion: (String?) -> Void
    /// Das Land wurde in der Ortsansicht gelöscht.
    let onDeleteCountry: () -> Void

    @Query private var countries: [Country]
    @Query private var cities: [City]
    /// Region je Stadt, einmal aus den Punkten gebaut.
    private let regionIds: [Int: String]

    init(focus: CountryFocus, selectedRegion: String?, place: Binding<PlaceRef?>,
         onSelectRegion: @escaping (String?) -> Void, onDeleteCountry: @escaping () -> Void) {
        self.focus = focus
        self.selectedRegion = selectedRegion
        self._place = place
        self.onSelectRegion = onSelectRegion
        self.onDeleteCountry = onDeleteCountry
        self.regionIds = Dictionary(focus.pins.compactMap { pin in pin.regionId.map { (pin.id, $0) } },
                                    uniquingKeysWith: { first, _ in first })
        let code = focus.code
        _countries = Query(filter: #Predicate<Country> { $0.isoCode == code })
        _cities = Query(filter: #Predicate<City> { $0.countryCode == code },
                        sort: \City.lastVisited, order: .reverse)
    }

    private struct RegionSummary: Identifiable {
        let id: String
        let name: String
        let cities: [City]
        let days: Int
        var lastVisited: Date { cities.map(\.lastVisited).max() ?? .distantPast }
        var firstVisited: Date { cities.map(\.firstVisited).min() ?? .distantPast }
    }

    private func regionId(of city: City) -> String? {
        regionIds[city.geonamesId]
    }

    private var regionSummaries: [RegionSummary] {
        let grouped = Dictionary(grouping: cities) { regionId(of: $0) ?? "" }
        return grouped.compactMap { id, cities -> RegionSummary? in
            guard let region = RegionIndex.shared.region(id: id) else { return nil }
            return RegionSummary(id: id, name: PlaceNames.region(region), cities: cities, days: focus.regionDays[id] ?? 0)
        }
        .sorted { $0.lastVisited > $1.lastVisited }
    }

    var body: some View {
        List {
            if let selectedRegion, let region = RegionIndex.shared.region(id: selectedRegion) {
                header(title: PlaceNames.region(region), subtitle: CountryNames.name(for: focus.code),
                       place: .region(region.id))
                citySection(cities.filter { regionId(of: $0) == selectedRegion })
            } else {
                header(title: CountryNames.name(for: focus.code), subtitle: countryDates, place: .country(focus.code))
                let summaries = regionSummaries
                if summaries.isEmpty {
                    citySection(cities)
                } else {
                    regionSection(summaries)
                    let withoutRegion = cities.filter { regionId(of: $0) == nil }
                    if !withoutRegion.isEmpty { citySection(withoutRegion, title: String(localized: "Other cities")) }
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .animation(.default, value: selectedRegion)
        .sheet(item: $place) { place in
            PlaceSheet(place: place, onDeleted: {
                if case .country = place { onDeleteCountry() }
            })
        }
    }

    private var countryDates: String? {
        guard let country = countries.first else { return nil }
        let first = country.firstVisited.formatted(date: .abbreviated, time: .omitted)
        let last = country.lastVisited.formatted(date: .abbreviated, time: .omitted)
        return first == last ? first : String(localized: "First \(first) · last \(last)")
    }

    private func header(title: String, subtitle: String?, place: PlaceRef) -> some View {
        Section {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { self.place = place } label: {
                    Label("Days", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
        }
    }

    private func regionSection(_ summaries: [RegionSummary]) -> some View {
        Section(String(localized: "\(summaries.count) regions")) {
            ForEach(summaries) { summary in
                Button {
                    onSelectRegion(summary.id)
                } label: {
                    HStack {
                        VisitRow(title: summary.name,
                                 subtitle: String(localized: "\(summary.cities.count) cities"),
                                 first: summary.firstVisited, last: summary.lastVisited)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func citySection(_ cities: [City], title: String? = nil) -> some View {
        Section(title ?? String(localized: "\(cities.count) cities")) {
            if cities.isEmpty {
                Text("No city with 15,000+ residents recorded nearby.")
                    .foregroundStyle(.secondary)
            }
            ForEach(cities) { city in
                Button {
                    place = .city(city.geonamesId)
                } label: {
                    HStack {
                        VisitRow(title: PlaceNames.city(city), first: city.firstVisited, last: city.lastVisited)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension City {
    /// Stadtmitte laut GeoNames.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
}
