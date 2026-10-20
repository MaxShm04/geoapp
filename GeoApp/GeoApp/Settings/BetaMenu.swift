import StoreKit
import SwiftUI

extension View {
    /// Beta-Knopf oben links mit dem Beta-Menü. Nur in Debug-Builds; in Release bleibt die View unverändert.
    func betaMenuButton() -> some View {
        #if DEBUG
        modifier(BetaMenuButton())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct BetaMenuButton: ViewModifier {
    @State private var showsMenu = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Beta") { showsMenu = true }
                }
            }
            .sheet(isPresented: $showsMenu) {
                BetaMenuView()
            }
    }
}

/// Testschalter, Pro-Freischaltung und Test-Abo beenden, für Tests auf dem eigenen Gerät.
/// iOS kann ein Abo aus der App heraus nicht sofort beenden: „Turn off auto-renew“ kündigt zum Periodenende,
/// „Act as not subscribed“ wirkt sofort, aber nur lokal.
struct BetaMenuView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BetaSettings.testControlsKey) private var showsTestControls = true
    @State private var showsManageSubscriptions = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show test controls", isOn: $showsTestControls)
                } footer: {
                    Text("Test data, the location check and the diagnostic log in Settings. Turn off to see Settings as a regular user.")
                }

                Section {
                    Toggle("Unlock Pro", isOn: Binding(
                        get: { store.betaProOverride },
                        set: { store.setBetaProOverride($0) }
                    ))
                } footer: {
                    Text("Unlocks all Pro features on this device, including the widgets. Nothing is purchased.")
                }

                Section {
                    Toggle("Act as not subscribed", isOn: Binding(
                        get: { store.betaIgnoresSubscription },
                        set: { store.setBetaIgnoresSubscription($0) }
                    ))
                    Button("Turn off auto-renew") { showsManageSubscriptions = true }
                        .disabled(!store.isEntitled)
                } header: {
                    Text("Test subscription")
                } footer: {
                    Text("Act as not subscribed treats a test purchase as ended right away, also in the widgets. The purchase itself stays. Turn off auto-renew cancels it in StoreKit; it then ends at the end of its period, not right away. To remove a test purchase at once, delete it in Xcode under Debug › StoreKit › Manage Transactions.")
                }

                Section {
                } footer: {
                    Text("Only in debug builds from Xcode. App Store and TestFlight builds don’t include this menu.")
                }
            }
            .tint(.accentColor)
            .navigationTitle("Beta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .presentationDetents([.medium, .large])
    }
}
#endif
