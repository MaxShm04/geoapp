import AppIntents
import Foundation
import GeoCore
import SwiftData

/// "Wie viele Länder dieses Jahr?" als Kurzbefehl (Entscheidung D11). Läuft im App-Prozess,
/// ohne die Oberfläche zu öffnen.
struct CountriesThisYearIntent: AppIntent {
    static let title: LocalizedStringResource = "Countries this year"
    static let description = IntentDescription("Tells you in how many countries the app recorded you this year.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let year = DayKey.year(DayKey.today())
        let count = Self.count(context: Store.shared.mainContext, year: year)
        return .result(value: count, dialog: IntentDialog(stringLiteral: Self.answer(count: count, year: year)))
    }

    /// Anzahl der Länder mit erfassten Tagen in `year`. Ein Fehler beim Lesen zählt als 0.
    static func count(context: ModelContext, year: Int) -> Int {
        let visits = (try? context.fetch(FetchDescriptor<DayVisit>())) ?? []
        let countries = Set(visits.filter { DayKey.year($0.day) == year }.map(\.countryCode))
        return countries.count
    }

    /// Antwortsatz, etwa "You’ve been to 5 countries in 2026.". Das Jahr steht als Text, damit
    /// es nie ein Tausendertrennzeichen bekommt.
    @MainActor
    static func answer(count: Int, year: Int, locale: Locale = .current) -> String {
        let yearText = String(year)
        if count == 0 {
            return L10n.string("No countries recorded in \(yearText) yet.", locale: locale)
        }
        return L10n.string("You’ve been to \(count) countries in \(yearText).", locale: locale)
    }
}
