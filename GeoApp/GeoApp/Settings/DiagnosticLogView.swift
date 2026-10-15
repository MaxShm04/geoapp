import SwiftData
import SwiftUI

/// Zeigt, wann und wie die App erfasst hat. Enthält keine Koordinaten.
struct DiagnosticLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiagnosticEntry.timestamp, order: .reverse) private var entries: [DiagnosticEntry]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Log ist leer", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Neue Einträge erscheinen, solange das Diagnose-Log eingeschaltet ist."))
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            Spacer()
                            Text(entry.source.label)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        Text(place(for: entry))
                        Text(entry.outcome)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnose-Log")
        .toolbar {
            Button("Leeren", role: .destructive) {
                try? context.delete(model: DiagnosticEntry.self)
                try? context.save()
            }
            .disabled(entries.isEmpty)
        }
    }

    private func place(for entry: DiagnosticEntry) -> String {
        var parts: [String] = []
        if let city = entry.cityName { parts.append(city) }
        if let district = entry.districtName, district != entry.cityName { parts.append(district) }
        if let code = entry.countryCode { parts.append(CountryNames.name(for: code)) }
        if let km = entry.distanceToCityCenterKm {
            parts.append("\(km.formatted(.number.precision(.fractionLength(1)))) km zur Mitte")
        }
        if entry.reducedAccuracy { parts.append("ungefähr") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}
