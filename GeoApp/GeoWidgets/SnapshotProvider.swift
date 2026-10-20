import StoreKit
import SwiftUI
import WidgetKit

/// Ein Eintrag der Widgets: Momentaufnahme der App plus Pro-Status.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let unlocked: Bool
}

/// Liefert die Einträge eines Widgets (Entscheidungen D8 und D9).
/// Liest nur die Momentaufnahme aus der App Group, nie den Store.
struct SnapshotProvider: TimelineProvider {
    let kind: WidgetKind

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: .placeholder, unlocked: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = AppGroup.containerURL.flatMap { WidgetSnapshot.load(from: WidgetSnapshot.url(in: $0)) }
        let kind = kind
        // Der Abschluss wird genau einmal aufgerufen; er ist nicht `Sendable`, aber die Aufgabe läuft auf demselben Akteur.
        nonisolated(unsafe) let finish = completion
        Task {
            // Pro wird bei jeder Aktualisierung bei StoreKit erfragt, nichts davon wird gespeichert.
            let entitled = await Self.isPro()
            // Schalter aus dem Beta-Menü in der App Group, in Release immer aus.
            let defaults = BetaSettings.sharedDefaults
            let pro = ProRules.unlocked(entitled: entitled,
                                        betaOverride: BetaSettings.proOverride(in: defaults),
                                        ignoresSubscription: BetaSettings.ignoresSubscription(in: defaults))
            let entry = SnapshotEntry(date: .now, snapshot: snapshot, unlocked: kind == WidgetKind.free || pro)
            // Neu laden zum nächsten Tag; die App lädt die Zeitpläne zusätzlich bei jeder Änderung neu.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
                ?? Date.now.addingTimeInterval(86_400)
            finish(Timeline(entries: [entry], policy: .after(tomorrow)))
        }
    }

    /// Fragt StoreKit nach den Berechtigungen und wendet dieselbe Regel wie die App an.
    private static func isPro() async -> Bool {
        var facts: [EntitlementFact] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            facts.append(EntitlementFact(productID: transaction.productID,
                                         revoked: transaction.revocationDate != nil,
                                         expires: transaction.expirationDate,
                                         isUpgraded: transaction.isUpgraded))
        }
        return ProRules.isPro(facts: facts)
    }
}
