import GeoCore
import SwiftData
import SwiftUI

/// Statistik je Jahr (T19). Die Übersicht ist für das laufende Jahr frei, Details und andere Jahre brauchen Pro (D10).
struct StatisticsScreen: View {
    @Query private var visits: [DayVisit]
    @AppStorage(AppSettings.homeRegionOverride) private var homeOverride = ""
    @Environment(ProStore.self) private var store
    @State private var selection = YearFilter.year(DayKey.year(DayKey.today()))
    @State private var showsPaywall = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var today: Int { DayKey.today() }
    private var currentYear: Int { DayKey.year(today) }

    /// Auswahl als Jahr für die Statistik, `nil` für alle Zeit.
    private var statsYear: Int? {
        if case .year(let year) = selection { return year }
        return nil
    }

    var body: some View {
        let journal = Journal.make(visits: visits, homeOverride: homeOverride, today: today)
        let years = journal.years(currentYear: currentYear)
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView("No statistics yet", systemImage: "chart.bar",
                                           description: Text("Statistics fill in as the app records your places."))
                } else {
                    ScrollView {
                        content(journal.statistics(year: statsYear))
                            .padding()
                    }
                }
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        choice(.year(currentYear))
                        ForEach(years.filter { $0 != currentYear }, id: \.self) { year in
                            choice(.year(year))
                        }
                        choice(.all)
                    } label: {
                        // Text statt Symbol, damit das gewählte Jahr in der Leiste sichtbar ist.
                        title(for: selection)
                    }
                }
            }
            .sheet(isPresented: $showsPaywall) { PaywallView() }
            .onChange(of: store.isPro) { _, isPro in
                // Nach Ende des Abos fällt die Auswahl auf das laufende Jahr zurück.
                if !ProGate.allows(.statistics, year: selection, currentYear: currentYear, isPro: isPro) {
                    selection = .year(currentYear)
                }
            }
        }
    }

    /// Übersicht mit vier Kacheln, darunter die Details oder ein Hinweis auf Pro.
    private func content(_ stats: YearStatistics) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Countries", value: stats.countryCodes.count)
                StatTile(title: "Cities", value: stats.cityIds.count)
                StatTile(title: "New places",
                         value: stats.newCountryCodes.count + stats.newCityIds.count,
                         caption: Text("\(stats.newCountryCodes.count) countries")
                            + Text(" · ")
                            + Text("\(stats.newCityIds.count) cities"))
                StatTile(title: "Travel days", value: stats.travelDays)
            }
            if ProGate.allowsStatisticsDetail(isPro: store.isPro) {
                StatisticsDetail(stats: stats)
            } else {
                LockedCard("Full statistics",
                           message: "Days per country, travel days per month and your longest trip, for every year.")
            }
            Text("Days without a recording count where you were last seen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Eintrag im Jahresmenü. Gesperrte Auswahl zeigt ein Schloss und öffnet die Paywall.
    private func choice(_ value: YearFilter) -> some View {
        let allowed = ProGate.allows(.statistics, year: value, currentYear: currentYear, isPro: store.isPro)
        return Button {
            if allowed {
                selection = value
            } else {
                showsPaywall = true
            }
        } label: {
            if !allowed {
                Label { title(for: value) } icon: { Image(systemName: "lock") }
            } else if value == selection {
                Label { title(for: value) } icon: { Image(systemName: "checkmark") }
            } else {
                title(for: value)
            }
        }
    }

    private func title(for value: YearFilter) -> Text {
        switch value {
        case .all: Text("All time")
        case .year(let year): year == currentYear ? Text("This year") : Text(verbatim: String(year))
        }
    }
}
