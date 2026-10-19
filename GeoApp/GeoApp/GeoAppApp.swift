import SwiftUI

@main
struct GeoAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var proStore = ProStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(LocationService.shared)
                .environment(proStore)
                .task { proStore.start() }
        }
        .modelContainer(Store.shared)
    }
}
