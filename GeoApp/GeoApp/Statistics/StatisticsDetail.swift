import Charts
import GeoCore
import SwiftUI

/// Statistik im Detail, nur mit Pro (D10): Tage je Land, Reisetage je Monat, längste Reise und neue Orte (T19).
struct StatisticsDetail: View {
    let stats: YearStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection("Days per country") { daysPerCountry }
            DetailSection("Travel days per month") { travelDaysChart }
            DetailSection("Longest trip") { longestTrip }
            DetailSection("New places") { newPlaces }
        }
    }

    /// Tage je Land, mit einem Balken relativ zum Land mit den meisten Tagen.
    @ViewBuilder
    private var daysPerCountry: some View {
        let maxDays = Double(stats.daysPerCountry.first?.days ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(stats.daysPerCountry, id: \.code) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        countryRow(entry.code)
                        Spacer()
                        Text("\(entry.days) days")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProportionBar(fraction: Double(entry.days) / maxDays)
                }
            }
        }
    }

    /// Reisetage je Monat als Säulen.
    private var travelDaysChart: some View {
        // Monate als Zahl, beschriftet mit einem Buchstaben: kurze Namen würden auf Deutsch abgeschnitten.
        let symbols = Calendar.current.veryShortMonthSymbols
        let names = Calendar.current.monthSymbols
        return Chart {
            ForEach(stats.travelDaysPerMonth.indices, id: \.self) { index in
                BarMark(x: .value("Month", index + 1),
                        y: .value("Days", stats.travelDaysPerMonth[index]),
                        width: .fixed(14))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(names[index])
            }
        }
        .chartXScale(domain: 0.5...12.5)
        .chartXAxis {
            AxisMarks(values: Array(1...12)) { value in
                AxisValueLabel {
                    if let month = value.as(Int.self) { Text(symbols[month - 1]) }
                }
            }
        }
        .frame(height: 160)
    }

    @ViewBuilder
    private var longestTrip: some View {
        if let trip = stats.longestTrip {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: CountryNames.flag(for: trip.mainCountryCode))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: CountryNames.name(for: trip.mainCountryCode))
                    Text(verbatim: dateRange(trip))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(trip.dayCount) days")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No trips in this period.")
                .foregroundStyle(.secondary)
        }
    }

    /// Neue Länder, dann neue Städte, je höchstens zehn.
    @ViewBuilder
    private var newPlaces: some View {
        let countries = stats.newCountryCodes.prefix(10)
        let cities = stats.newCityIds.prefix(10)
        if countries.isEmpty && cities.isEmpty {
            Text("No new places in this period.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(countries, id: \.self) { code in
                    countryRow(code)
                }
                ForEach(cities, id: \.self) { id in
                    Text(verbatim: PlaceNames.city(id: id))
                }
            }
        }
    }

    /// Flagge und Name eines Landes.
    private func countryRow(_ code: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: CountryNames.flag(for: code))
            Text(verbatim: CountryNames.name(for: code))
        }
    }

    /// Von bis einer Reise, etwa "3 Mar – 9 Mar 2026".
    private func dateRange(_ trip: Trip) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        guard let start = DayKey.date(trip.startDay), let end = DayKey.date(trip.endDay) else { return "" }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

/// Abschnitt mit Überschrift auf einer ruhigen Karte.
private struct DetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Dünner Balken, Anteil von 0 bis 1.
private struct ProportionBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}
