import Foundation
import GeoCore
import SwiftData

/// Testdaten zum Ausprobieren der Länderansicht: Reisen in Bayern mit unterschiedlicher
/// Aufenthaltsdauer, von 12 Tagen in München bis zu kurzen Stopps in Kleinstädten.
///
/// Die Einträge laufen über den normalen `VisitRecorder` mit der Quelle `.demo` und den
/// Stadtmitten aus GeoNames. Beim Ausschalten werden genau diese Besuche wieder entfernt,
/// echte Besuche bleiben unberührt.
enum MockData {
    /// Größte Städte Bayerns mit festen Aufenthaltstagen, danach kleinere Orte mit einem Tag.
    private static let daysForLargest = [12, 5, 3, 2, 2, 1, 1, 1]
    /// Jede wievielte der übrigen bayerischen Städte als kurzer Stopp dazukommt.
    private static let smallTownStep = 6

    static func enable(context: ModelContext) {
        let lookup = GeoLookup.shared
        guard let bavaria = RegionIndex.shared.regions(in: "DE").first(where: { $0.name == "Bayern" }) else { return }
        let towns = lookup.cities.cities
            .filter { $0.countryCode == "DE" && $0.regionId == bavaria.id }
            .sorted { $0.population > $1.population }

        var plan: [(GeoCore.City, Int)] = zip(towns, daysForLargest).map { ($0, $1) }
        plan += towns.dropFirst(daysForLargest.count).enumerated()
            .filter { $0.offset % smallTownStep == 0 }
            .map { ($0.element, 1) }

        let recorder = VisitRecorder(context: context, diagnosticsEnabled: { false })
        var day = Date.now.addingTimeInterval(-120 * 86_400)
        for (city, days) in plan {
            for _ in 0..<days {
                recorder.record(latitude: city.latitude, longitude: city.longitude, horizontalAccuracy: 50,
                                speed: -1, timestamp: day, source: .demo)
                day.addTimeInterval(86_400)
            }
            day.addTimeInterval(86_400 / 2)
        }
        WidgetSync.refresh(context: context)
    }

    #if DEBUG
    /// Nur zum Prüfen im Simulator (`-enableMockTrips YES`): Reisen über zwei Jahre mit München als
    /// Heimat, als Testdaten (`.demo`), die beim Ausschalten der Testdaten wieder verschwinden.
    static func enableTrips(context: ModelContext, now: Date = .now) {
        let munich = 2867714
        // (Stadt, Beginn in Tagen vor heute, Tage). Mehrere Städte nacheinander bilden eine Reise.
        let stays: [(Int, Int, Int)] = [
            (2988507, 480, 5),                                   // Paris, Juni des Vorjahres
            (2761369, 400, 3),                                   // Wien
            (3164527, 160, 2), (3164603, 158, 2), (3176959, 156, 2), (3169070, 154, 2),  // Italien
            (2911298, 60, 3),                                    // Hamburg
        ]
        var awayDays = Set<Int>()
        for (_, start, days) in stays { for offset in 0..<days { awayDays.insert(start - offset) } }
        let recorder = VisitRecorder(context: context, diagnosticsEnabled: { false })
        func record(_ id: Int, daysAgo: Int, hour: Double) {
            guard let city = GeoLookup.shared.cities.city(id: id) else { return }
            let timestamp = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(-daysAgo) * 86_400 + hour * 3600)
            recorder.record(latitude: city.latitude, longitude: city.longitude, horizontalAccuracy: 50,
                            speed: -1, timestamp: timestamp, source: .demo)
        }
        // Zuhause alle paar Tage, damit die Heimatregion erkannt wird und Lücken sich schließen.
        for daysAgo in stride(from: 500, through: 0, by: -4) where !awayDays.contains(daysAgo) {
            record(munich, daysAgo: daysAgo, hour: 9)
        }
        for (id, start, days) in stays {
            for offset in 0..<days { record(id, daysAgo: start - offset, hour: 13) }
        }
        // Abreise- und Rückkehrtage: morgens zu Hause, abends unterwegs und umgekehrt.
        for (start, end) in [(480, 476), (400, 398), (160, 153), (60, 58)] {
            record(munich, daysAgo: start, hour: 7)
            record(munich, daysAgo: end, hour: 21)
        }
        record(2766824, daysAgo: 20, hour: 13)                   // Salzburg als Tagesausflug
        record(munich, daysAgo: 20, hour: 20)
        WidgetSync.refresh(context: context)
    }
    #endif

    static func disable(context: ModelContext) {
        try? Deletion.deleteDemo(context: context)
    }
}
