import StoreKit
import SwiftUI

/// Paywall mit den beiden Pro-Abos. Die Preise und Probezeit-Hinweise kommen von StoreKit.
struct PaywallView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Was Pro freischaltet, so wie es ausgeliefert ist (Phase 2, D10).
    static let featureKeys: [String] = [
        "Every year on the map and in your trips",
        "Detailed statistics for every year",
        "All widgets for your Home Screen",
    ]

    /// SF-Symbol je Funktion, in derselben Reihenfolge wie `featureKeys`.
    private static let featureSymbols = ["calendar", "chart.bar", "square.grid.2x2"]

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            marketing
        }
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStoreControlStyle(.picker)
        .storeButton(.visible, for: .restorePurchases)
        // Den Schließen-Knopf zeigt StoreKit selbst, wenn die Ansicht als Blatt erscheint.
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: ProStore.Links.terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: ProStore.Links.privacy, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, _ in
            await store.refreshFromStoreKit()
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    /// Kurze Erklärung oben auf der Paywall, ohne Werbesprache.
    private var marketing: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Pro")
                .font(.largeTitle.bold())
            Text("More out of your places. Your support keeps the app free of ads and tracking.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.featureKeys.indices, id: \.self) { index in
                    // Feste Breite für die Symbole, damit die Texte untereinander beginnen.
                    Label {
                        Text(LocalizedStringKey(Self.featureKeys[index]))
                    } icon: {
                        Image(systemName: Self.featureSymbols[index]).frame(width: 24)
                    }
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Your places stay on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
}
