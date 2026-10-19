import StoreKit
import SwiftUI

/// Paywall mit den beiden Pro-Abos. Die Preise und Probezeit-Hinweise kommen von StoreKit.
struct PaywallView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

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
            Text("Pro adds upcoming features: your travel years, statistics and widgets. Your support keeps the app free of ads and tracking.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your places stay on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
}
