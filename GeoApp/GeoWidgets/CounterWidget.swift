import SwiftUI
import WidgetKit

/// Zähler: Länder und Städte insgesamt. Das kostenlose Widget.
struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.counter.kind, provider: SnapshotProvider(kind: .counter)) { entry in
            CounterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("Counter"))
        .description(LocalizedStringResource("Countries and cities you have visited."))
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct CounterWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.unlocked {
            LockedWidgetView()
        } else if let snapshot = entry.snapshot {
            counter(snapshot)
        } else {
            MissingSnapshotView()
        }
    }

    private func counter(_ snapshot: WidgetSnapshot) -> some View {
        let isSmall = family == .systemSmall
        return VStack(alignment: .leading, spacing: 2) {
            // Zahl mit Einheit, damit die große Zahl allein nicht rätselhaft bleibt.
            Text("\(snapshot.countriesTotal) countries")
                .font(.system(size: isSmall ? 28 : 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("AccentColor"))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(snapshot.citiesTotal) cities")
                .font(.subheadline)
            Text("\(snapshot.countriesThisYear) countries in \(String(snapshot.year))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isSmall ? 4 : 0)
        .accessibilityElement(children: .combine)
    }
}
