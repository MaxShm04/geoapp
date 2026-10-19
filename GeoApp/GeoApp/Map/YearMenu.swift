import GeoCore
import SwiftUI

/// Jahresfilter neben dem Zähler der Karte. Jahre ohne Pro zeigen ein Schloss und öffnen die Paywall.
struct YearMenu: View {
    /// Wert für `@AppStorage`, siehe `YearFilter.storageValue`.
    @Binding var selection: String
    /// Jahre mit Daten, absteigend. Das laufende Jahr steht immer als "This year" oben.
    let years: [Int]
    let currentYear: Int
    let isPro: Bool

    @State private var showsPaywall = false

    private var current: YearFilter {
        YearFilter(storageValue: selection) ?? .all
    }

    /// Alle Jahre außer dem laufenden, neueste zuerst.
    private var otherYears: [Int] {
        years.filter { $0 != currentYear }
    }

    var body: some View {
        Menu {
            option(.all)
            option(.year(currentYear))
            ForEach(otherYears, id: \.self) { year in
                option(.year(year))
            }
        } label: {
            HStack(spacing: 4) {
                title(current)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("Year filter")
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
    }

    /// Eine Zeile im Menü. Häkchen für die Auswahl, Schloss für gesperrte Jahre.
    private func option(_ filter: YearFilter) -> some View {
        let locked = !ProGate.allows(.yearFilter, year: filter, currentYear: currentYear, isPro: isPro)
        return Button {
            if locked {
                showsPaywall = true
            } else {
                selection = filter.storageValue
            }
        } label: {
            if locked {
                Label { title(filter) } icon: { Image(systemName: "lock") }
            } else if filter == current {
                Label { title(filter) } icon: { Image(systemName: "checkmark") }
            } else {
                title(filter)
            }
        }
    }

    /// Text eines Filters. Jahreszahlen ohne Tausendertrennzeichen.
    private func title(_ filter: YearFilter) -> Text {
        switch filter {
        case .all: Text("All years")
        case .year(let year) where year == currentYear: Text("This year")
        case .year(let year): Text(verbatim: String(year))
        }
    }
}
