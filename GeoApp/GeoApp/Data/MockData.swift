import Foundation
import GeoCore
import SwiftData

#if DEBUG
/// Testdaten (nur Debug): vier Jahre Reisen mit München als Heimat, damit jede Funktion etwas zu zeigen hat.
///
/// Szenarien, alle relativ zu heute:
/// - Heimat München jeden zweiten Tag, ältere Jahre jede Woche; dazu Tagesausflüge in andere bayerische
///   Städte (mehrere Städte in einer Region, mehrere Städte an einem Tag)
/// - Tagesausflug ins Ausland ohne Übernachtung (Salzburg)
/// - Reise durch mehrere Länder (München → Innsbruck → Bozen → Verona → Venedig)
/// - Italien ein zweites Mal mit Pause dazwischen (Rom, Florenz)
/// - kurze Reise (Hamburg, drei Tage) und neues Land im laufenden Jahr (Kopenhagen)
/// - laufende Reise bis heute (Zürich)
/// - Reise über Silvester (Wien, Dezember → Januar)
/// - frühere Jahre: Berlin, Island mit einem Tag ohne Stadt in der Nähe, Réunion (Übersee),
///   lange Reise Lissabon → Porto mit einem Tag ohne Erfassung (Lücke), Paris → Lyon
///
/// Die Einträge laufen über den normalen `VisitRecorder` mit der Quelle `.demo` und festen Punkten
/// (Stadtmitten laut GeoNames, ein Punkt im Inneren Islands). Gespeichert werden wie immer nur Stadt,
/// Land und Tag. Beim Ausschalten werden genau diese Besuche wieder entfernt, echte Besuche bleiben.
enum MockData {
    /// Ein fester Punkt für die Testdaten, keine Position einer Person.
    struct Spot {
        let latitude: Double
        let longitude: Double
    }

    enum Spots {
        static let munich = Spot(latitude: 48.1374, longitude: 11.5755)
        static let bavaria = [
            Spot(latitude: 48.3705, longitude: 10.8978),   // Augsburg
            Spot(latitude: 49.4521, longitude: 11.0767),   // Nürnberg
            Spot(latitude: 49.0134, longitude: 12.1016),   // Regensburg
            Spot(latitude: 49.7913, longitude: 9.9534),    // Würzburg
            Spot(latitude: 48.7665, longitude: 11.4258),   // Ingolstadt
            Spot(latitude: 49.8988, longitude: 10.9028),   // Bamberg
            Spot(latitude: 47.8571, longitude: 12.1181),   // Rosenheim
            Spot(latitude: 47.4921, longitude: 11.0955),   // Garmisch-Partenkirchen
        ]
        static let salzburg = Spot(latitude: 47.8095, longitude: 13.0550)
        static let innsbruck = Spot(latitude: 47.2692, longitude: 11.4041)
        static let bolzano = Spot(latitude: 46.4983, longitude: 11.3548)
        static let verona = Spot(latitude: 45.4384, longitude: 10.9916)
        static let venice = Spot(latitude: 45.4408, longitude: 12.3155)
        static let rome = Spot(latitude: 41.9028, longitude: 12.4964)
        static let florence = Spot(latitude: 43.7696, longitude: 11.2558)
        static let hamburg = Spot(latitude: 53.5511, longitude: 9.9937)
        static let copenhagen = Spot(latitude: 55.6761, longitude: 12.5683)
        static let zurich = Spot(latitude: 47.3769, longitude: 8.5417)
        static let vienna = Spot(latitude: 48.2082, longitude: 16.3738)
        static let berlin = Spot(latitude: 52.5200, longitude: 13.4050)
        static let reykjavik = Spot(latitude: 64.1466, longitude: -21.9426)
        static let akureyri = Spot(latitude: 65.6835, longitude: -18.0878)
        /// Im Hochland, weit weg von jeder Stadt mit 15.000 Einwohnern: zählt nur als Island.
        static let icelandHighlands = Spot(latitude: 64.8, longitude: -18.0)
        static let saintDenis = Spot(latitude: -20.8789, longitude: 55.4481)
        static let saintPierre = Spot(latitude: -21.3393, longitude: 55.4781)
        static let lisbon = Spot(latitude: 38.7223, longitude: -9.1393)
        static let porto = Spot(latitude: 41.1579, longitude: -8.6291)
        static let paris = Spot(latitude: 48.8566, longitude: 2.3522)
        static let lyon = Spot(latitude: 45.7640, longitude: 4.8357)
    }

    /// Plan der Testdaten: Zeitpunkte und Orte, noch nicht gespeichert.
    struct Plan {
        let now: Date
        let calendar: Calendar
        private(set) var entries: [(date: Date, spot: Spot)] = []
        /// Tage unterwegs (yyyymmdd); an diesen Tagen gibt es keinen Eintrag zu Hause.
        private(set) var awayDays: Set<Int> = []

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
        }

        var today: Date { calendar.startOfDay(for: now) }
        var year: Int { calendar.component(.year, from: now) }

        func date(daysAgo: Int, hour: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: -daysAgo, hour: hour), to: today) ?? today
        }

        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? today
        }

        mutating func at(_ spot: Spot, _ date: Date) {
            entries.append((date, spot))
        }

        /// Ein Aufenthalt über mehrere Tage, ab `start` jeden Tag mittags. Die Tage zählen als unterwegs.
        mutating func stay(_ spot: Spot, from start: Date, days: Int, skipping skipped: Set<Int> = []) {
            for offset in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                markAway(day)
                if !skipped.contains(offset) { at(spot, day) }
            }
        }

        mutating func markAway(_ date: Date) {
            awayDays.insert(VisitRules.dayKey(for: date, calendar: calendar))
        }

        /// Abreise: morgens zu Hause, abends am Ziel.
        mutating func leave(on date: Date, to spot: Spot) {
            let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
            markAway(date)
            at(Spots.munich, morning)
            at(spot, evening)
        }

        /// Nichts aus der Zukunft, in zeitlicher Reihenfolge.
        mutating func finish() {
            let limit = now
            entries = entries.filter { $0.date <= limit }.sorted { $0.date < $1.date }
        }

        /// Rückkehr: morgens noch unterwegs, abends zu Hause.
        mutating func come(home date: Date, from spot: Spot) {
            let morning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
            let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
            markAway(date)
            at(spot, morning)
            at(Spots.munich, evening)
        }
    }

    /// Alle Szenarien als Plan. `now` legt fest, wo heute ist; nichts liegt in der Zukunft.
    static func plan(now: Date, calendar: Calendar = .current) -> Plan {
        var plan = Plan(now: now, calendar: calendar)
        let year = plan.year
        func ago(_ days: Int, _ hour: Int = 13) -> Date { plan.date(daysAgo: days, hour: hour) }

        // Tagesausflug ins Ausland, ohne Übernachtung: zählt nicht als Reise.
        plan.at(Spots.munich, ago(20, 8))
        plan.at(Spots.salzburg, ago(20, 13))
        plan.at(Spots.munich, ago(20, 20))

        // Mehrere Länder in einer Reise, mit zwei Städten an einem Tag (Verona, abends Venedig).
        plan.leave(on: ago(150), to: Spots.innsbruck)
        plan.at(Spots.innsbruck, ago(149, 9))
        plan.at(Spots.bolzano, ago(149, 17))
        plan.stay(Spots.bolzano, from: ago(148), days: 1)
        plan.at(Spots.verona, ago(147, 11))
        plan.at(Spots.venice, ago(147, 19))
        plan.stay(Spots.venice, from: ago(146), days: 1)
        plan.markAway(ago(149))
        plan.markAway(ago(147))
        plan.come(home: ago(145), from: Spots.venice)

        // Italien ein zweites Mal, mit Pause dazwischen.
        plan.leave(on: ago(71), to: Spots.rome)
        plan.stay(Spots.rome, from: ago(70), days: 3)
        plan.stay(Spots.florence, from: ago(67), days: 2)
        plan.come(home: ago(65), from: Spots.florence)

        // Kurze Reise: die kürzeste, die als Reise zählt (ein ganzer Tag ohne Heimat); neue Stadt im laufenden Jahr.
        plan.leave(on: ago(41), to: Spots.hamburg)
        plan.stay(Spots.hamburg, from: ago(40), days: 1)
        plan.come(home: ago(39), from: Spots.hamburg)

        // Neues Land im laufenden Jahr.
        plan.leave(on: ago(30), to: Spots.copenhagen)
        plan.stay(Spots.copenhagen, from: ago(29), days: 2)
        plan.come(home: ago(27), from: Spots.copenhagen)

        // Laufende Reise bis heute.
        plan.leave(on: ago(1), to: Spots.zurich)
        plan.markAway(now)
        plan.at(Spots.zurich, max(plan.today, now.addingTimeInterval(-3600)))

        // Reise über Silvester, vor zwei Jahren in das vorige Jahr hinein.
        plan.leave(on: plan.date(year - 2, 12, 28, hour: 12), to: Spots.vienna)
        plan.stay(Spots.vienna, from: plan.date(year - 2, 12, 29, hour: 13), days: 5)
        plan.come(home: plan.date(year - 1, 1, 3, hour: 12), from: Spots.vienna)

        // Voriges Jahr: Berlin (andere Region), Island mit einem Tag ohne Stadt, Réunion (Übersee).
        plan.leave(on: plan.date(year - 1, 5, 10, hour: 12), to: Spots.berlin)
        plan.stay(Spots.berlin, from: plan.date(year - 1, 5, 11, hour: 13), days: 1)
        plan.come(home: plan.date(year - 1, 5, 12, hour: 12), from: Spots.berlin)

        plan.leave(on: plan.date(year - 1, 7, 3, hour: 12), to: Spots.reykjavik)
        plan.stay(Spots.reykjavik, from: plan.date(year - 1, 7, 4, hour: 13), days: 1)
        plan.stay(Spots.icelandHighlands, from: plan.date(year - 1, 7, 5, hour: 13), days: 1)
        plan.stay(Spots.akureyri, from: plan.date(year - 1, 7, 6, hour: 13), days: 2)
        plan.at(Spots.icelandHighlands, plan.date(year - 1, 7, 8, hour: 10))
        plan.at(Spots.reykjavik, plan.date(year - 1, 7, 8, hour: 19))
        plan.markAway(plan.date(year - 1, 7, 8, hour: 12))
        plan.come(home: plan.date(year - 1, 7, 9, hour: 12), from: Spots.reykjavik)

        plan.leave(on: plan.date(year - 1, 11, 10, hour: 12), to: Spots.saintDenis)
        plan.stay(Spots.saintDenis, from: plan.date(year - 1, 11, 11, hour: 13), days: 2)
        plan.stay(Spots.saintPierre, from: plan.date(year - 1, 11, 13, hour: 13), days: 2)
        plan.stay(Spots.saintDenis, from: plan.date(year - 1, 11, 15, hour: 13), days: 1)
        plan.come(home: plan.date(year - 1, 11, 16, hour: 12), from: Spots.saintDenis)

        // Vor zwei Jahren: lange Reise mit einem Tag ohne Erfassung (die Lücke füllt die Statistik).
        plan.leave(on: plan.date(year - 2, 9, 5, hour: 12), to: Spots.lisbon)
        plan.stay(Spots.lisbon, from: plan.date(year - 2, 9, 6, hour: 13), days: 6, skipping: [4])
        plan.stay(Spots.porto, from: plan.date(year - 2, 9, 12, hour: 13), days: 4)
        plan.come(home: plan.date(year - 2, 9, 16, hour: 12), from: Spots.porto)

        // Vor drei Jahren: Paris und Lyon.
        plan.leave(on: plan.date(year - 3, 6, 2, hour: 12), to: Spots.paris)
        plan.stay(Spots.paris, from: plan.date(year - 3, 6, 3, hour: 13), days: 4)
        plan.stay(Spots.lyon, from: plan.date(year - 3, 6, 7, hour: 13), days: 2)
        plan.come(home: plan.date(year - 3, 6, 9, hour: 12), from: Spots.lyon)

        // Zu Hause: im letzten Jahr jeden zweiten Tag, davor jede Woche, seit Anfang des Jahres vor drei Jahren.
        // Jeder achte Tag zu Hause bringt einen Ausflug in eine andere bayerische Stadt.
        let start = plan.date(year - 3, 1, 1, hour: 9)
        let totalDays = plan.calendar.dateComponents([.day], from: start, to: plan.today).day ?? 0
        var homeCount = 0
        for daysAgo in stride(from: totalDays, through: 0, by: -1) {
            let step = daysAgo <= 400 ? 2 : 7
            guard daysAgo % step == 0 else { continue }
            let morning = plan.date(daysAgo: daysAgo, hour: 9)
            guard !plan.awayDays.contains(VisitRules.dayKey(for: morning, calendar: plan.calendar)) else { continue }
            plan.at(Spots.munich, morning)
            homeCount += 1
            if homeCount % 8 == 0 {
                let town = Spots.bavaria[(homeCount / 8) % Spots.bavaria.count]
                plan.at(town, plan.date(daysAgo: daysAgo, hour: 14))
                plan.at(Spots.munich, plan.date(daysAgo: daysAgo, hour: 20))
            }
        }

        plan.finish()
        return plan
    }

    static func enable(context: ModelContext, now: Date = .now) {
        let recorder = VisitRecorder(context: context, diagnosticsEnabled: { false })
        for entry in plan(now: now).entries {
            recorder.record(latitude: entry.spot.latitude, longitude: entry.spot.longitude, horizontalAccuracy: 50,
                            speed: -1, timestamp: entry.date, source: .demo)
        }
        WidgetSync.refresh(context: context)
    }

    static func disable(context: ModelContext) {
        try? Deletion.deleteDemo(context: context)
    }
}
#endif
