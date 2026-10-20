import GeoCore
import SwiftData
import SwiftUI

/// Ortsansicht als eigenes Blatt (von der Karte), mit Fertig-Knopf.
struct PlaceSheet: View {
    let place: PlaceRef
    var onDeleted: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlaceDetailView(place: place, onDeleted: onDeleted)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Wann man an einem Ort war: erster Tab eine Liste der Aufenthalte, zweiter Tab ein Kalender,
/// in dem jeder Besuchstag eingekreist ist. Städte und Länder lassen sich hier löschen.
struct PlaceDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case days
        case calendar
        var id: Self { self }
        var title: LocalizedStringResource {
            switch self {
            case .days: "Days"
            case .calendar: "Calendar"
            }
        }
    }

    let place: PlaceRef
    var onDeleted: (() -> Void)?

    @Query private var visits: [DayVisit]
    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .days
    @State private var confirmsDelete = false

    init(place: PlaceRef, onDeleted: (() -> Void)? = nil) {
        self.place = place
        self.onDeleted = onDeleted
        switch place {
        case .city(let id):
            let cityID: Int? = id
            _visits = Query(filter: #Predicate<DayVisit> { $0.geonamesId == cityID })
        case .country(let code):
            _visits = Query(filter: #Predicate<DayVisit> { $0.countryCode == code })
        case .region, .district:
            // Region und Kreis brauchen den Rückfall auf die Stadtmitte, siehe `PlaceRef.days(in:)`.
            _visits = Query()
        }
    }

    private var currentYear: Int { DayKey.year(DayKey.today()) }

    var body: some View {
        let days = PlaceDays.make(days: place.days(in: visits), currentYear: currentYear, isPro: store.isPro)
        List {
            Section {
                Text(summary(days))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))

                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch tab {
            case .days: dateSections(days)
            case .calendar: calendarSections(days)
            }

            if !days.lockedYears.isEmpty {
                Section {
                    LockedCard("Earlier years", message: "Dates from earlier years are part of Pro.")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if place.canDelete, tab == .days {
                Section {
                    Button("Delete this place", role: .destructive) { confirmsDelete = true }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(place.name)
        .alert(String(localized: "Delete \(place.name)?"), isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            switch place {
            case .country: Text("All visits in this country and its cities will be removed.")
            default: Text("All visits in this city will be removed.")
            }
        }
    }

    /// "Germany · 23 days".
    private func summary(_ days: PlaceDays) -> String {
        let count = L10n.string("\(days.totalDays) days", locale: .current)
        return [place.context, count].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Liste

    @ViewBuilder private func dateSections(_ days: PlaceDays) -> some View {
        ForEach(days.years, id: \.year) { year in
            Section {
                ForEach(year.stays, id: \.self) { stay in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.stayText(stay))
                        Spacer()
                        Text(L10n.string("\(stay.dayCount) days", locale: .current))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                HStack {
                    Text(String(year.year))
                    Spacer()
                    Text(L10n.string("\(year.dayCount) days", locale: .current))
                }
            }
        }
    }

    /// "Tue, 12 May" für einen Tag, "12 – 23 May" für mehrere. Das Jahr steht im Abschnittskopf.
    static func stayText(_ stay: Stay, calendar: Calendar = .current) -> String {
        guard let first = DayKey.date(stay.first, calendar: calendar),
              let last = DayKey.date(stay.last, calendar: calendar) else { return "" }
        if stay.first == stay.last {
            return first.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return (first..<last).formatted(.interval.day().month(.abbreviated))
    }

    // MARK: Kalender

    @ViewBuilder private func calendarSections(_ days: PlaceDays) -> some View {
        let visited = Set(days.shownDays)
        ForEach(days.months, id: \.self) { month in
            Section(Self.monthTitle(month)) {
                MonthGrid(month: month, visited: visited)
                    .padding(.vertical, 4)
            }
        }
    }

    static func monthTitle(_ month: Int) -> String {
        DayKey.date(PlaceCalendar.dayKey(month: month, day: 1))?.formatted(.dateTime.month(.wide).year()) ?? ""
    }

    // MARK: Löschen

    private func delete() {
        switch place {
        case .city(let id): try? Deletion.deleteCity(id, context: context)
        case .country(let code): try? Deletion.deleteCountry(code, context: context)
        case .region, .district: return
        }
        dismiss()
        onDeleted?()
    }
}

/// Monatsblatt: Wochentage oben, jeder Besuchstag als Zahl in einem gefüllten Kreis.
struct MonthGrid: View {
    let month: Int
    let visited: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let calendar = Calendar.current
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(Self.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(PlaceCalendar.monthGrid(month: month, firstWeekday: calendar.firstWeekday).enumerated()),
                    id: \.offset) { _, day in
                if let day {
                    cell(day, isVisited: visited.contains(PlaceCalendar.dayKey(month: month, day: day)))
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func cell(_ day: Int, isVisited: Bool) -> some View {
        Text(String(day))
            .font(.callout.weight(isVisited ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isVisited ? Color.white : Color.primary)
            .frame(width: 34, height: 34)
            .background {
                if isVisited { Circle().fill(Color.accentColor) }
            }
    }

    /// "Visited on 3 May, 4 May and 12 May".
    private var accessibilityText: String {
        let days = visited.filter { PlaceCalendar.month(of: $0) == month }.sorted()
        let names = days.compactMap { DayKey.date($0)?.formatted(.dateTime.day().month(.wide)) }
        return String(localized: "Visited on \(names.formatted(.list(type: .and)))")
    }

    /// Sehr kurze Wochentagsnamen, beginnend mit `calendar.firstWeekday`.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[start...] + symbols[..<start])
    }
}
