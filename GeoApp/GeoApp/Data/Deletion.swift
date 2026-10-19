import Foundation
import GeoCore
import SwiftData

/// Löschen einzelner Einträge und aller Daten. Danach bleiben keine verwaisten Einträge zurück.
enum Deletion {
    /// Löscht ein Land mit seinen Städten und allen Tagen dort.
    static func deleteCountry(_ code: String, context: ModelContext) throws {
        try context.delete(model: DayVisit.self, where: #Predicate { $0.countryCode == code })
        try context.delete(model: City.self, where: #Predicate { $0.countryCode == code })
        try context.delete(model: Country.self, where: #Predicate { $0.isoCode == code })
        try removeOrphans(affectedCountries: [], context: context)
        try context.save()
        WidgetSync.refresh(context: context)
    }

    /// Löscht eine Stadt mit ihren Tagen. Das Land bleibt, solange es dort noch andere Besuche gibt.
    static func deleteCity(_ geonamesId: Int, context: ModelContext) throws {
        let id: Int? = geonamesId
        let visits = try context.fetch(FetchDescriptor<DayVisit>(predicate: #Predicate { $0.geonamesId == id }))
        let cities = try context.fetch(FetchDescriptor<City>(predicate: #Predicate { $0.geonamesId == geonamesId }))
        let affected = Set(visits.map(\.countryCode) + cities.map(\.countryCode))
        visits.forEach(context.delete)
        cities.forEach(context.delete)
        try removeOrphans(affectedCountries: affected, context: context)
        try context.save()
        WidgetSync.refresh(context: context)
    }

    /// Löscht alles: Länder, Städte, Tage und das Diagnose-Log.
    static func deleteAll(context: ModelContext) throws {
        try context.delete(model: DayVisit.self)
        try context.delete(model: City.self)
        try context.delete(model: Country.self)
        try context.delete(model: DiagnosticEntry.self)
        try context.save()
        WidgetSync.refresh(context: context)
    }

    /// Löscht die Testdaten. Städte, die auch echte Besuche haben, bleiben und bekommen ihren
    /// Zeitraum aus den verbliebenen Tagen.
    static func deleteDemo(context: ModelContext) throws {
        let removed = try context.fetch(FetchDescriptor<DayVisit>(predicate: #Predicate { $0.isDemo }))
        guard !removed.isEmpty else { return }
        let affectedCities = Set(removed.compactMap(\.geonamesId))
        let affectedCountries = Set(removed.map(\.countryCode))
        removed.forEach(context.delete)

        let remaining = try context.fetch(FetchDescriptor<DayVisit>(predicate: #Predicate { !$0.isDemo }))
        let visitsByCity = Dictionary(grouping: remaining.filter { $0.geonamesId.map(affectedCities.contains) == true },
                                      by: { $0.geonamesId! })
        for city in try context.fetch(FetchDescriptor<City>()) where affectedCities.contains(city.geonamesId) {
            guard let visits = visitsByCity[city.geonamesId],
                  let first = visits.map(\.firstSeen).min(), let last = visits.map(\.lastSeen).max() else { continue }
            city.firstVisited = first
            city.lastVisited = last
        }
        try removeOrphans(affectedCountries: affectedCountries, context: context)
        try context.save()
        WidgetSync.refresh(context: context)
    }

    /// Entfernt Städte und Länder ohne Tage. Bei betroffenen Ländern wird der Zeitraum
    /// aus den verbliebenen Tagen und Städten neu bestimmt.
    private static func removeOrphans(affectedCountries: Set<String>, context: ModelContext) throws {
        // Gelöschte, aber noch nicht gespeicherte Einträge nicht mitzählen.
        let visits = try context.fetch(FetchDescriptor<DayVisit>()).filter { !$0.isDeleted }
        let cityIDs = Set(visits.compactMap(\.geonamesId))
        for city in try context.fetch(FetchDescriptor<City>()) where !cityIDs.contains(city.geonamesId) {
            context.delete(city)
        }
        let visitsByCountry = Dictionary(grouping: visits, by: \.countryCode)
        let cities = try context.fetch(FetchDescriptor<City>()).filter { cityIDs.contains($0.geonamesId) }
        for country in try context.fetch(FetchDescriptor<Country>()) {
            guard let countryVisits = visitsByCountry[country.isoCode], !countryVisits.isEmpty else {
                context.delete(country)
                continue
            }
            guard affectedCountries.contains(country.isoCode) else { continue }
            let countryCities = cities.filter { $0.countryCode == country.isoCode }
            let dates = countryVisits.flatMap { [$0.firstSeen, $0.lastSeen] }
                + countryCities.flatMap { [$0.firstVisited, $0.lastVisited] }
            if let first = dates.min(), let last = dates.max() {
                country.firstVisited = first
                country.lastVisited = last
            }
        }
    }
}
