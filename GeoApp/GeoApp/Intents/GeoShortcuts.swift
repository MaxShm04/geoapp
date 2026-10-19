import AppIntents

/// Kurzbefehle, die ohne Einrichtung in der Kurzbefehle-App und für Siri erscheinen (Entscheidung D11).
/// Die Phrasen stehen in `AppShortcuts.xcstrings`.
struct GeoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CountriesThisYearIntent(),
            phrases: [
                "How many countries this year in \(.applicationName)",
                "Countries this year in \(.applicationName)",
                "How many countries have I visited this year with \(.applicationName)"
            ],
            shortTitle: "Countries this year",
            systemImageName: "globe.europe.africa"
        )
    }
}
