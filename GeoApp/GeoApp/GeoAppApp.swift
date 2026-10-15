import SwiftUI

@main
struct GeoAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(LocationService.shared)
        }
        .modelContainer(Store.shared)
    }
}
