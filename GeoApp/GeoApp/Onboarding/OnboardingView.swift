import CoreLocation
import SwiftUI

/// Ein Erklär-Screen, danach die zwei Berechtigungsschritte, die iOS vorgibt:
/// erst "Beim Verwenden", dann "Immer".
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(LocationService.self) private var location
    @State private var showsPermission = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if showsPermission {
                PermissionStep(authorization: location.authorization, onFinish: onFinish)
            } else {
                intro
            }
            Spacer()
        }
        .padding(32)
        .animation(.default, value: showsPermission)
        .animation(.default, value: location.authorization)
    }

    private var intro: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Your travel map fills in by itself")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("In the background, the app quietly notes which countries and cities you have been to and shows them on a world map. Only city, country and time are stored, never your exact position, and none of it leaves your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue") { showsPermission = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

private struct PermissionStep: View {
    let authorization: CLAuthorizationStatus
    let onFinish: () -> Void

    @Environment(LocationService.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.alwaysRequested) private var alwaysRequested = false
    /// Solange der iOS-Dialog für "Immer" offen ist, bleibt der Schritt stehen.
    @State private var awaitingAlwaysAnswer = false

    var body: some View {
        content
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, awaitingAlwaysAnswer else { return }
                // Die neue Berechtigung kommt erst kurz nach der Rückkehr aus dem Dialog an. Sonst
                // blitzt "Immer fehlt noch" auf, obwohl gerade "Immer" erlaubt wurde.
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    awaitingAlwaysAnswer = false
                }
            }
    }

    private func askForAlways() {
        awaitingAlwaysAnswer = true
        location.requestAlways()
        // Hat iOS schon einmal gefragt, erscheint kein Dialog und die App bleibt aktiv.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if UIApplication.shared.applicationState == .active { awaitingAlwaysAnswer = false }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            actions
        }
    }

    private var stuckOnWhenInUse: Bool {
        authorization == .authorizedWhenInUse && alwaysRequested && !awaitingAlwaysAnswer
    }

    private var symbol: String {
        switch authorization {
        case .authorizedAlways: "checkmark.circle"
        case .denied, .restricted: "location.slash"
        default: "location"
        }
    }

    private var title: LocalizedStringResource {
        switch authorization {
        case .notDetermined: "Step 1 of 2: While Using"
        case .authorizedWhenInUse where stuckOnWhenInUse: "Always still missing"
        case .authorizedWhenInUse: "Step 2 of 2: Always"
        case .authorizedAlways: "All set"
        default: "Location is off"
        }
    }

    private var message: LocalizedStringResource {
        switch authorization {
        case .notDetermined:
            "First, iOS asks whether the app may see your location while you use it. Your position is only matched to a city and then discarded."
        case .authorizedWhenInUse where stuckOnWhenInUse:
            "Without Always, the app only records while it is open. You can change this at any time in the iOS Settings under Location."
        case .authorizedWhenInUse:
            "So the map fills in without your help, the app needs your location in the background too. It is only woken briefly for larger changes of place."
        case .authorizedAlways where location.hasReducedAccuracy:
            "The app now records countries and cities. Precise location is off, though: iOS then shifts your location by a few kilometers, so cities may be off."
        case .authorizedAlways:
            "The app now records countries and cities on larger changes of place. You don’t need to do anything else."
        default:
            "Without location, the app cannot record places. You can allow it in the iOS Settings."
        }
    }

    @ViewBuilder private var actions: some View {
        switch authorization {
        case .notDetermined:
            primary("Allow While Using") { location.requestWhenInUse() }
        case .authorizedWhenInUse where stuckOnWhenInUse:
            primary("Open iOS Settings", action: openSettings)
            Button("Later", action: onFinish)
        case .authorizedWhenInUse:
            primary("Allow Always", action: askForAlways)
        case .authorizedAlways:
            primary("Let’s go", action: onFinish)
            if location.hasReducedAccuracy {
                Button("Turn on precise location", action: openSettings)
            }
        default:
            primary("Open iOS Settings", action: openSettings)
            Button("Later", action: onFinish)
        }
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
