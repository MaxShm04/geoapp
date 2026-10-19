import GeoCore
import SwiftData
import SwiftUI

/// Heimatregion wählen: automatisch erkannt oder eine der eigenen Regionen (Entscheidung D4).
struct HomeRegionView: View {
    @Query private var visits: [DayVisit]
    @AppStorage(AppSettings.homeRegionOverride) private var homeOverride = ""

    var body: some View {
        let journal = Journal.make(visits: visits, homeOverride: homeOverride, today: DayKey.today())
        let areas = AreaDays.top(journal.days)
        Group {
            if areas.isEmpty {
                ContentUnavailableView("No regions yet", systemImage: "house",
                                       description: Text("Your home region is found automatically once the app has recorded a few days."))
            } else {
                Form {
                    Section {
                        automaticRow(detected: journal.detectedHome)
                    } footer: {
                        Text("Automatic uses the region where you spent the most days in the last 90 days.")
                    }

                    Section {
                        ForEach(areas) { area in
                            areaRow(area)
                        }
                    } header: {
                        Text("Your regions")
                    }
                }
            }
        }
        .tint(.accentColor)
        .navigationTitle("Home region")
    }

    /// Automatisch erkannte Heimat, ohne Auswahl.
    private func automaticRow(detected: String?) -> some View {
        Button {
            homeOverride = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic")
                    Text(detected.map { PlaceNames.area($0) } ?? String(localized: "Not known yet"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if homeOverride.isEmpty {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    /// Eine Region mit Flagge, Land und Anzahl Tagen; tippen wählt sie als Heimat.
    private func areaRow(_ area: AreaDays) -> some View {
        Button {
            homeOverride = area.key
        } label: {
            HStack(spacing: 12) {
                Text(CountryNames.flag(for: area.countryCode))
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlaceNames.area(area.key))
                    (Text(CountryNames.name(for: area.countryCode)) + Text(" · ") + Text("\(area.days) days"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if homeOverride == area.key {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

/// Ein Gebiet mit der Zahl verschiedener Tage darin.
private struct AreaDays: Identifiable {
    let key: String
    let countryCode: String
    let days: Int

    var id: String { key }

    /// Höchstens 20 Gebiete, nach Tagen absteigend, bei Gleichstand nach Schlüssel.
    static func top(_ places: [PlaceDay], limit: Int = 20) -> [AreaDays] {
        var daysByArea: [String: Set<Int>] = [:]
        for place in places {
            daysByArea[place.areaKey, default: []].insert(place.day)
        }
        return daysByArea
            .map { key, days in
                // Ist der Schlüssel eine Region, zählt ihr Land; sonst ist er selbst ein Ländercode.
                AreaDays(key: key, countryCode: RegionIndex.shared.region(id: key)?.countryCode ?? key, days: days.count)
            }
            .sorted { $0.days != $1.days ? $0.days > $1.days : $0.key < $1.key }
            .prefix(limit)
            .map { $0 }
    }
}
