import GeoCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppSettings.registerDefaults()
        // Core Location startet die App bei Ortswechseln auch ohne Oberfläche neu.
        // Der Location-Manager muss deshalb schon hier entstehen, nicht erst in einer View.
        _ = LocationService.shared
        // Geodaten laden und Städte angleichen, ohne den Start aufzuhalten.
        Task {
            await Store.bootstrap()
            #if DEBUG
            // Für Tests im Simulator: `-enableMockData YES` schaltet die Testdaten wie der Schalter ein.
            if UserDefaults.standard.bool(forKey: "enableMockData"),
               !UserDefaults.standard.bool(forKey: AppSettings.mockDataEnabled) {
                MockData.enable(context: Store.shared.mainContext)
                UserDefaults.standard.set(true, forKey: AppSettings.mockDataEnabled)
            }
            if UserDefaults.standard.bool(forKey: "enableMockTrips"),
               !UserDefaults.standard.bool(forKey: AppSettings.mockDataEnabled) {
                MockData.enableTrips(context: Store.shared.mainContext)
                UserDefaults.standard.set(true, forKey: AppSettings.mockDataEnabled)
            }
            #endif
        }
        return true
    }
}
