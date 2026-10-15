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
            Text("Deine Reisekarte füllt sich von selbst")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Die App merkt sich im Hintergrund, in welchen Ländern und Städten du warst, und zeigt sie auf einer Weltkarte. Gespeichert werden nur Stadt, Land und Zeitpunkt, nie deine genaue Position, und nichts davon verlässt dein iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Weiter") { showsPermission = true }
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
                if phase == .active { awaitingAlwaysAnswer = false }
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
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
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

    private var title: String {
        switch authorization {
        case .notDetermined: "Schritt 1 von 2: Beim Verwenden"
        case .authorizedWhenInUse where stuckOnWhenInUse: "Immer fehlt noch"
        case .authorizedWhenInUse: "Schritt 2 von 2: Immer"
        case .authorizedAlways: "Alles bereit"
        default: "Standort ist aus"
        }
    }

    private var message: String {
        switch authorization {
        case .notDetermined:
            "Zuerst fragt iOS, ob die App deinen Standort beim Verwenden sehen darf. Die Position wird nur einer Stadt zugeordnet und dann verworfen."
        case .authorizedWhenInUse where stuckOnWhenInUse:
            "Ohne Immer erfasst die App nur, wenn sie geöffnet ist. Du kannst das jederzeit in den iOS-Einstellungen unter Standort ändern."
        case .authorizedWhenInUse:
            "Damit sich die Karte ohne dein Zutun füllt, braucht die App den Standort auch im Hintergrund. Sie wird nur bei größeren Ortswechseln kurz geweckt."
        case .authorizedAlways where location.hasReducedAccuracy:
            "Die App erfasst ab jetzt Länder und Städte. Genaue Position ist aber aus: iOS verschiebt den Standort dann um einige Kilometer, Städte können danebenliegen."
        case .authorizedAlways:
            "Die App erfasst ab jetzt Länder und Städte bei größeren Ortswechseln. Du musst nichts weiter tun."
        default:
            "Ohne Standort kann die App keine Orte erfassen. Du kannst ihn in den iOS-Einstellungen erlauben."
        }
    }

    @ViewBuilder private var actions: some View {
        switch authorization {
        case .notDetermined:
            primary("Beim Verwenden erlauben") { location.requestWhenInUse() }
        case .authorizedWhenInUse where stuckOnWhenInUse:
            primary("iOS-Einstellungen öffnen", action: openSettings)
            Button("Später", action: onFinish)
        case .authorizedWhenInUse:
            primary("Immer erlauben", action: askForAlways)
        case .authorizedAlways:
            primary("Los geht's", action: onFinish)
            if location.hasReducedAccuracy {
                Button("Genaue Position einschalten", action: openSettings)
            }
        default:
            primary("iOS-Einstellungen öffnen", action: openSettings)
            Button("Später", action: onFinish)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
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
