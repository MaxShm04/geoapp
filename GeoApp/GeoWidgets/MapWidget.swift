import SwiftUI
import UIKit
import WidgetKit

/// Weltkarte mit den besuchten Ländern. Pro. Das Bild schreibt die App in die App Group (Entscheidung D8).
struct MapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.map.kind, provider: SnapshotProvider(kind: .map)) { entry in
            MapWidgetView(entry: entry)
                .containerBackground(Self.ocean, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("Map"))
        .description(LocalizedStringResource("Your world map with the countries you have visited."))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }

    /// Meerfarbe der Kartenbilder (wie `WidgetMapRenderer`), damit Ränder neben der Karte nicht auffallen.
    static let ocean = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
            : UIColor(red: 0.93, green: 0.95, blue: 0.96, alpha: 1)
    })
}

struct MapWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

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
        // Das Bild füllt die Fläche und wird beschnitten; der Hinweis liegt auf dem Rahmen, nicht auf dem Bild.
        Color.clear
            .overlay { mapImage }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if family == .systemSmall {
                    Text("\(snapshot.countriesTotal) countries")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(snapshot.countriesTotal) countries"))
    }

    /// Hell oder dunkel, je nach Systemdarstellung. Ohne Bild erscheint ein Globus.
    @ViewBuilder
    private var mapImage: some View {
        let name = colorScheme == .dark ? WidgetSnapshot.mapDarkFileName : WidgetSnapshot.mapLightFileName
        if let url = AppGroup.containerURL?.appending(path: name),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}
