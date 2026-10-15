import Foundation
import GeoCore
import OSLog
import SwiftData

/// Gleicht gespeicherte Städte nach einem Update der Städtedaten an.
///
/// Wird ein Ort zum Teil einer größeren Stadt (etwa Stepney zu London), wandern seine Besuche
/// zu dieser Stadt. Grundlage ist die gespeicherte Stadtmitte aus GeoNames, nicht die Position der Person.
enum CityRemapping {
    private static let log = Logger(subsystem: "de.max.geoapp", category: "Daten")

    static func run(context: ModelContext, lookup: GeoLookup = .shared) {
        guard let stored = try? context.fetch(FetchDescriptor<City>()) else { return }
        var changed = false
        for old in stored where lookup.cities.city(id: old.geonamesId) == nil {
            changed = true
            guard let target = lookup.cities.nearest(lat: old.centerLatitude, lon: old.centerLongitude,
                                                     radiusKm: GeoLookup.cityRadiusKm,
                                                     preferredCountry: old.countryCode) else {
                log.info("\(old.name, privacy: .public) hat keine Nachfolgestadt, Besuche zählen nur fürs Land")
                DayVisits.reassign(from: old.geonamesId, to: nil, context: context)
                context.delete(old)
                continue
            }
            log.info("\(old.name, privacy: .public) wird zu \(target.name, privacy: .public)")
            let targetID = target.id
            let existing = try? context.fetch(FetchDescriptor<City>(predicate: #Predicate { $0.geonamesId == targetID })).first
            if let existing {
                existing.firstVisited = min(existing.firstVisited, old.firstVisited)
                existing.lastVisited = max(existing.lastVisited, old.lastVisited)
            } else {
                let new = City(from: target, visited: old.firstVisited)
                new.lastVisited = old.lastVisited
                context.insert(new)
            }
            DayVisits.reassign(from: old.geonamesId, to: target.id, context: context)
            context.delete(old)
        }
        if changed { try? context.save() }
    }
}
