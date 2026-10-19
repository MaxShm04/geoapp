import GeoCore
import SwiftUI

/// Details einer Reise: Zeitraum, Länder und Städte (T18).
struct TripDetailView: View {
    let trip: Trip

    var body: some View {
        List {
            Section("Dates") {
                Text(verbatim: TripRow.dateRange(trip, withYear: true))
                Text("\(trip.dayCount) days")
            }
            Section("Countries") {
                ForEach(trip.countryCodes, id: \.self) { code in
                    HStack(spacing: 12) {
                        Text(verbatim: CountryNames.flag(for: code))
                        Text(verbatim: CountryNames.name(for: code))
                    }
                }
            }
            if !trip.cityIds.isEmpty {
                Section("Cities") {
                    ForEach(trip.cityIds, id: \.self) { id in
                        Text(verbatim: PlaceNames.city(id: id))
                    }
                }
            }
        }
        .navigationTitle(CountryNames.name(for: trip.mainCountryCode))
        .navigationBarTitleDisplayMode(.inline)
    }
}
