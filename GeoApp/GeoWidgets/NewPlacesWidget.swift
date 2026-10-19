import SwiftUI
import WidgetKit

/// Neue Orte dieses Jahres: neue Länder, neue Städte und ihre Namen. Pro.
struct NewPlacesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.newPlaces.kind, provider: SnapshotProvider(kind: .newPlaces)) { entry in
            NewPlacesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("New places"))
        .description(LocalizedStringResource("New countries and cities this year."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NewPlacesWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.unlocked {
            LockedWidgetView()
        } else if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            MissingSnapshotView()
        }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        // Klein: zwei Namen, mittel: drei.
        let limit = family == .systemSmall ? 2 : 3
        let names = Array(snapshot.newPlaceNames.prefix(limit).enumerated())
        return VStack(alignment: .leading, spacing: 4) {
            Text("New in \(String(snapshot.year))")
                .font(.headline)
            (Text("\(snapshot.newCountriesThisYear) countries") + Text(verbatim: " · ") + Text("\(snapshot.newCitiesThisYear) cities"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if names.isEmpty {
                Text("No new places yet this year.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
        .accessibilityElement(children: .combine)
    }
}
