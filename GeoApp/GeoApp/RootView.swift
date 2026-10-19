import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage(AppSettings.onboardingDone) private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var location

    var body: some View {
        Group {
            if onboardingDone {
                TabView {
                    MapScreen()
                        .tabItem { Label("Map", systemImage: "map") }
                    ListScreen()
                        .tabItem { Label("List", systemImage: "list.bullet") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                OnboardingView { onboardingDone = true }
            }
        }
        .safeAreaInset(edge: .top) {
            if let error = Store.openError {
                Label("Saved places could not be loaded. New places will be lost when the app quits. (\(error))",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.25))
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, onboardingDone { location.captureOnAppOpen() }
        }
    }
}
