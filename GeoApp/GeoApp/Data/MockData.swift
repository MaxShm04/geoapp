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
    }

    static func disable(context: ModelContext) {
        try? Deletion.deleteDemo(context: context)
    }
}
