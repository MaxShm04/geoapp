import SwiftUI
import WidgetKit

/// Gesperrter Zustand eines Pro-Widgets. Ein Tipp öffnet das Paywall über `geoapp://pro`.
struct LockedWidgetView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.title3)
            Text("Pro")
                .font(.headline)
            Text("Part of Pro. Tap to learn more.")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .widgetURL(URL(string: "geoapp://pro"))
    }
}

/// Hinweis, solange die App noch keine Momentaufnahme geschrieben hat.
struct MissingSnapshotView: View {
    var body: some View {
        Text("Open the app once to fill this widget.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
    }
}
