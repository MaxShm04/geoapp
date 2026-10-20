import GeoCore
import SwiftData
import SwiftUI

/// Reisen als Zeitleiste (T18): die Reisen eines Jahres, neueste zuerst. Jahre außer dem laufenden sind Pro (D10).
/// Oben links öffnet ein Knopf alle Länder und Städte als durchsuchbare Liste.
struct TripsScreen: View {
    @Environment(ProStore.self) private var store
    @Query private var visits: [DayVisit]
    @AppStorage(AppSettings.homeRegionOverride) private var homeOverride = ""
    @State private var year = DayKey.year(DayKey.today())
    @State private var showsPaywall = false
    @State private var showsPlaces = false

    var body: some View {
        let today = DayKey.today()
        let currentYear = DayKey.year(today)
        let journal = Journal.make(visits: visits, homeOverride: homeOverride, today: today)
        let shownYear = isAllowed(year, currentYear: currentYear) ? year : currentYear
        let trips = journal.trips.filter { DayKey.year($0.startDay) == shownYear }

        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "suitcase",
                                           description: Text("A trip starts when you spend a night away from your home region."))
                } else {
                    List {
                        Section {
                            ForEach(trips) { trip in
                                NavigationLink {
                                    TripDetailView(trip: trip)
                                } label: {
                                    TripRow(trip: trip, year: shownYear)
                                }
                            }
                        } footer: {
                            if let home = journal.home {
                                Text("Home region: \(PlaceNames.area(home)). Change it in Settings.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Places", systemImage: "list.bullet") { showsPlaces = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    yearMenu(years: journal.years(currentYear: currentYear), shownYear: shownYear, currentYear: currentYear)
                }
            }
            .sheet(isPresented: $showsPaywall) { PaywallView() }
            .sheet(isPresented: $showsPlaces) { PlacesList() }
        }
    }

    /// Jahresmenü. Gesperrte Jahre zeigen ein Schloss und öffnen die Paywall statt der Auswahl.
    private func yearMenu(years: [Int], shownYear: Int, currentYear: Int) -> some View {
        Menu {
            ForEach(years, id: \.self) { value in
                Button {
                    if isAllowed(value, currentYear: currentYear) {
                        year = value
                    } else {
                        showsPaywall = true
                    }
                } label: {
                    if value == shownYear {
                        Label(yearName(value, currentYear: currentYear), systemImage: "checkmark")
                    } else if isAllowed(value, currentYear: currentYear) {
                        Text(verbatim: yearName(value, currentYear: currentYear))
                    } else {
                        Label(yearName(value, currentYear: currentYear), systemImage: "lock")
                    }
                }
            }
        } label: {
            // Text statt Symbol, damit das gewählte Jahr in der Leiste sichtbar ist.
            Text(yearName(shownYear, currentYear: currentYear))
        }
    }

    private func isAllowed(_ value: Int, currentYear: Int) -> Bool {
        ProGate.allows(.timeline, year: .year(value), currentYear: currentYear, isPro: store.isPro)
    }

    private func yearName(_ value: Int, currentYear: Int) -> String {
        value == currentYear ? String(localized: "This year") : String(value)
    }
}
