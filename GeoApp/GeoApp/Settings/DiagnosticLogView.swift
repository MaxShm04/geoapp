import SwiftData
import SwiftUI

/// Zeigt, wann und wie die App erfasst hat. Enthält keine Koordinaten.
struct DiagnosticLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiagnosticEntry.timestamp, order: .reverse) private var entries: [DiagnosticEntry]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Log is empty", systemImage: "doc.text.magnifyingglass",
                                       description: Text("New entries appear while the diagnostic log is turned on."))
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
                        Text(DiagnosticOutcome.text(for: entry.outcome))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnostic Log")
        .toolbar {
            Button("Clear", role: .destructive) {
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
            parts.append(String(localized: "\(km.formatted(.number.precision(.fractionLength(1)))) km to center"))
        }
        if entry.reducedAccuracy { parts.append(String(localized: "approximate")) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}
