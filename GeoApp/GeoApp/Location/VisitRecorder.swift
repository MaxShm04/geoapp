import Foundation
import GeoCore
import OSLog
import SwiftData

/// Verarbeitet eine Position in drei Schritten: Regeln prüfen, Land und Stadt zuordnen, speichern.
///
/// Die Koordinate kommt nur als Parameter herein und wird nur an `GeoLookup` weitergegeben.
/// Sie wird nirgends gespeichert oder geloggt und ist nach dem Aufruf verworfen.
/// `LocationService` ordnet im Hintergrund zu und ruft danach `record(match:…)` auf.
final class VisitRecorder {
    enum Outcome: Equatable {
        /// Der Ort ist an diesem Tag neu.
        case newDay(countryCode: String, cityName: String?)
        /// Der Ort war heute schon erfasst, `count` ist die Zahl der Erfassungen heute.
        case sameDay(countryCode: String, cityName: String?, count: Int)
        case rejected(RejectReason)
        case noCountry
    }

    static let shared = VisitRecorder(context: Store.shared.mainContext)

    private let context: ModelContext
    private let lookup: GeoLookup
    private let diagnosticsEnabled: () -> Bool
    private let log = Logger(subsystem: "de.max.geoapp", category: "Erfassung")

    init(context: ModelContext, lookup: GeoLookup = .shared,
         diagnosticsEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: AppSettings.diagnosticsEnabled) }) {
        self.context = context
        self.lookup = lookup
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    /// Alle drei Schritte auf einmal, für Tests und Testdaten.
    @discardableResult
    func record(latitude: Double, longitude: Double, horizontalAccuracy: Double, speed: Double,
                timestamp: Date, source: CaptureSource, reducedAccuracy: Bool = false) -> Outcome {
        if let reason = VisitRules.rejectReason(horizontalAccuracy: horizontalAccuracy, speed: speed) {
            return reject(reason, timestamp: timestamp, source: source, reducedAccuracy: reducedAccuracy)
        }
        return record(match: lookup.resolve(latitude: latitude, longitude: longitude),
                      timestamp: timestamp, source: source, reducedAccuracy: reducedAccuracy)
    }

    /// Regeln 1 und 3 haben die Position verworfen. Nur fürs Diagnose-Log.
    @discardableResult
    func reject(_ reason: RejectReason, timestamp: Date, source: CaptureSource, reducedAccuracy: Bool = false) -> Outcome {
        finish(.rejected(reason), source: source, timestamp: timestamp, reducedAccuracy: reducedAccuracy)
    }

    /// Speichert eine fertige Zuordnung. `nil` heißt: kein Land (offenes Meer).
    @discardableResult
    func record(match: GeoMatch?, timestamp: Date, source: CaptureSource, reducedAccuracy: Bool = false) -> Outcome {
        guard let match else {
            return finish(.noCountry, source: source, timestamp: timestamp, reducedAccuracy: reducedAccuracy)
        }
        let outcome = store(match, timestamp: timestamp, source: source)
        return finish(outcome, source: source, timestamp: timestamp, match: match, reducedAccuracy: reducedAccuracy)
    }

    /// Ein Fehler von Core Location, etwa kein Standort beim Öffnen. Nur fürs Diagnose-Log.
    func recordFailure(_ message: String, source: CaptureSource) {
        log.info("Kein Standort (\(source.rawValue, privacy: .public)): \(message, privacy: .public)")
        addDiagnostic(DiagnosticEntry(timestamp: .now, source: source, outcome: "kein Standort"))
        save()
    }

    private func store(_ match: GeoMatch, timestamp: Date, source: CaptureSource) -> Outcome {
        let code = match.countryCode
        let country = fetchCountry(code) ?? {
            let name = lookup.countries.shape(for: code)?.name ?? code
            let new = Country(isoCode: code, name: name, visited: timestamp)
            context.insert(new)
            return new
        }()
        country.firstVisited = min(country.firstVisited, timestamp)
        country.lastVisited = max(country.lastVisited, timestamp)

        var cityName: String?
        if let geoCity = match.city {
            let city = fetchCity(geoCity.id) ?? {
                let new = City(from: geoCity, visited: timestamp)
                context.insert(new)
                return new
            }()
            city.firstVisited = min(city.firstVisited, timestamp)
            city.lastVisited = max(city.lastVisited, timestamp)
            cityName = city.name
        }

        // Regel 4: ein Eintrag pro Ort und Tag, weitere Erfassungen zählen nur hoch.
        let (visit, isNew) = DayVisits.add(DayVisits.Entry(match: match, timestamp: timestamp, source: source),
                                           context: context)
        return isNew ? .newDay(countryCode: code, cityName: cityName)
            : .sameDay(countryCode: code, cityName: cityName, count: visit.captureCount)
    }

    private func finish(_ outcome: Outcome, source: CaptureSource, timestamp: Date, match: GeoMatch? = nil,
                        reducedAccuracy: Bool) -> Outcome {
        let text: String
        switch outcome {
        case .newDay: text = "neuer Tag"
        case .sameDay(_, _, let count): text = "heute schon erfasst (\(count)×)"
        case .rejected(.flight): text = "ignoriert: Flug"
        case .rejected(.inaccurate): text = "ignoriert: ungenau"
        case .rejected(.invalidAccuracy): text = "ignoriert: ungültig"
        case .noCountry: text = "kein Land"
        }
        // Nur Stadt, Land und Ergebnis ins System-Log, nie die Koordinate.
        log.info("\(source.rawValue, privacy: .public): \(text, privacy: .public) \(match?.city?.name ?? "", privacy: .public) \(match?.countryCode ?? "", privacy: .public)")
        addDiagnostic(DiagnosticEntry(timestamp: timestamp, source: source, outcome: text,
                                      cityName: match?.city?.name,
                                      districtName: match?.districtId.flatMap { DistrictIndex.shared.district(id: $0)?.name },
                                      countryCode: match?.countryCode,
                                      distanceToCityCenterKm: match?.distanceToCityCenterKm.map { ($0 * 10).rounded() / 10 },
                                      reducedAccuracy: reducedAccuracy))
        save()
        return outcome
    }

    private func addDiagnostic(_ entry: DiagnosticEntry) {
        guard diagnosticsEnabled() else { return }
        context.insert(entry)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            log.error("Speichern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchCountry(_ code: String) -> Country? {
        try? context.fetch(FetchDescriptor<Country>(predicate: #Predicate { $0.isoCode == code })).first
    }

    private func fetchCity(_ id: Int) -> City? {
        try? context.fetch(FetchDescriptor<City>(predicate: #Predicate { $0.geonamesId == id })).first
    }
}
