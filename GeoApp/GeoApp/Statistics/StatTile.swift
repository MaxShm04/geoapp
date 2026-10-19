import SwiftUI

/// Kachel mit einer Zahl in der Statistik-Übersicht (T19).
struct StatTile: View {
    let title: LocalizedStringKey
    let value: Int
    var caption: Text? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value, format: .number)
                .font(.title.bold())
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Ohne Untertitel bleibt die Zeile leer, damit alle Kacheln gleich hoch sind.
            (caption ?? Text(verbatim: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(caption == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
