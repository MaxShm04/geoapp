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

/// Testschalter und Pro-Freischaltung für Tests auf dem eigenen Gerät.
struct BetaMenuView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BetaSettings.testControlsKey) private var showsTestControls = true

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
        .presentationDetents([.medium, .large])
    }
}
#endif
