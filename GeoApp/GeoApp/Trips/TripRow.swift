import GeoCore
import SwiftUI

/// Zeile einer Reise: Flagge des Hauptlandes, Titel, Zeitraum und Zähler (T18).
struct TripRow: View {
    let trip: Trip
    /// Gewähltes Jahr. Das Jahr einer Datumsangabe steht nur dabei, wenn es davon abweicht.
    let year: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: CountryNames.flag(for: trip.mainCountryCode))
                .font(.largeTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    title
                        .font(.headline)
                    if trip.isOngoing {
                        Text("Ongoing")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                details
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Hauptland, bei mehreren Ländern mit Zusatz.
    private var title: Text {
        let name = CountryNames.name(for: trip.mainCountryCode)
        let others = trip.countryCodes.count - 1
        return others > 0 ? Text("\(name) and \(others) more") : Text(verbatim: name)
    }

    /// Zeitraum, Städte und Tage, durch Punkte getrennt.
    private var details: Text {
        let showsYear = DayKey.year(trip.startDay) != year || DayKey.year(trip.endDay) != year
        var line = Text(verbatim: Self.dateRange(trip, withYear: showsYear))
        if !trip.cityIds.isEmpty {
            line = line + Text(verbatim: " · ") + Text("\(trip.cityIds.count) cities")
        }
        return line + Text(verbatim: " · ") + Text("\(trip.dayCount) days")
    }

    /// Zeitraum der Reise. Ein Tag ohne Bindestrich, sonst Anfang und Ende. Das Jahr steht nur bei `withYear`.
    static func dateRange(_ trip: Trip, withYear: Bool) -> String {
        let format: Date.FormatStyle = withYear
            ? Date.FormatStyle.dateTime.day().month(.abbreviated).year()
            : Date.FormatStyle.dateTime.day().month(.abbreviated)
        let start = DayKey.date(trip.startDay).map { $0.formatted(format) } ?? ""
        guard trip.endDay != trip.startDay else { return start }
        let end = DayKey.date(trip.endDay).map { $0.formatted(format) } ?? ""
        return "\(start) – \(end)"
    }
}
