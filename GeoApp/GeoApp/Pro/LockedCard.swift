import SwiftUI

/// Ruhiger Hinweis an Stelle eines Pro-Inhalts, mit Knopf zur Paywall. Nie aufdringlich, nie beim Start.
struct LockedCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @State private var showsPaywall = false

    init(_ title: LocalizedStringKey, message: LocalizedStringKey) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lock")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Get Pro") { showsPaywall = true }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }
}
