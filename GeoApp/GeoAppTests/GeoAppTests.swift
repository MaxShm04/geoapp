import Foundation
import GeoCore
import SwiftData
import Testing
@testable import GeoApp

/// 00:30 Uhr Ortszeit an einem festen Tag, damit Erfassungen über den Tag nicht über Mitternacht laufen.
private let testDayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    .addingTimeInterval(30 * 60)

struct AppSettingsTests {
    @Test func defaultsAreRegistered() {
        AppSettings.registerDefaults()
        let defaults = UserDefaults.standard
        #expect(defaults.object(forKey: AppSettings.trackingEnabled) != nil)
        #expect(defaults.object(forKey: AppSettings.visitsEnabled) != nil)
    }
}

/// Besuchsregeln mit echter Zuordnung und einem Speicher nur im Arbeitsspeicher.
@MainActor
struct VisitRecorderTests {
    let container: ModelContainer
    let recorder: VisitRecorder
    var context: ModelContext { container.mainContext }
    let start = testDayStart

    init() throws {
        container = try Store.inMemory()
        recorder = VisitRecorder(context: container.mainContext, diagnosticsEnabled: { true })
    }

    @discardableResult
    func record(_ lat: Double, _ lon: Double, after hours: Double = 0, accuracy: Double = 50,
                speed: Double = -1, source: CaptureSource = .significantChange) -> VisitRecorder.Outcome {
        recorder.record(latitude: lat, longitude: lon, horizontalAccuracy: accuracy, speed: speed,
                        timestamp: start.addingTimeInterval(hours * 3600), source: source)
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func visits() throws -> [DayVisit] {
        try context.fetch(FetchDescriptor<DayVisit>(sortBy: [SortDescriptor(\.day)]))
    }

    @Test func firstVisitCreatesCountryCityAndDay() throws {
        #expect(record(52.52, 13.405) == .newDay(countryCode: "DE", cityName: "Berlin"))
        #expect(try count(Country.self) == 1)
        #expect(try count(GeoApp.City.self) == 1)
        #expect(try count(DayVisit.self) == 1)
    }

    @Test func sameCitySameDayOnlyCounts() throws {
        record(52.52, 13.405)
        #expect(record(52.53, 13.41, after: 3) == .sameDay(countryCode: "DE", cityName: "Berlin", count: 2))
        #expect(try count(DayVisit.self) == 1)
        let city = try #require(try context.fetch(FetchDescriptor<GeoApp.City>()).first)
        #expect(city.firstVisited == start)
        #expect(city.lastVisited == start.addingTimeInterval(3 * 3600))
    }

    /// Weckt iOS die App den ganzen Tag über am selben Ort, bleibt es ein Eintrag.
    @Test func twentyFourCapturesOnOneDayAreOneEntry() throws {
        for i in 0..<24 { record(52.52, 13.405, after: Double(i) * 0.9) }
        let visit = try #require(try visits().first)
        #expect(try count(DayVisit.self) == 1)
        #expect(visit.captureCount == 24)
        #expect(visit.firstSeen == start)
        #expect(visit.lastSeen == start.addingTimeInterval(23 * 0.9 * 3600))
    }

    @Test func sameCityNextDayIsNewEntry() throws {
        record(52.52, 13.405)
        #expect(record(52.52, 13.405, after: 24) == .newDay(countryCode: "DE", cityName: "Berlin"))
        #expect(try count(DayVisit.self) == 2)
        #expect(try count(GeoApp.City.self) == 1)
    }

    @Test func stayOverMidnightCountsTwoDays() throws {
        record(52.52, 13.405, after: 22.5)   // 23:00
        record(52.52, 13.405, after: 24.5)   // 01:00 am nächsten Tag
        #expect(try count(DayVisit.self) == 2)
        let focus = CountryFocus.make(code: "DE", cities: try context.fetch(FetchDescriptor<GeoApp.City>()),
                                      visits: try visits())
        #expect(focus.pins.first?.days == 2)
    }

    @Test func twoSourcesOnOneDayShareTheEntry() throws {
        record(52.52, 13.405, source: .significantChange)
        record(52.52, 13.405, after: 2, source: .visit)
        let visit = try #require(try visits().first)
        #expect(try count(DayVisit.self) == 1)
        #expect(visit.sources == [.significantChange, .visit])
    }

    @Test func routeBerlinParisRome() throws {
        record(52.52, 13.405)
        record(48.8566, 2.3522, after: 1, source: .visit)
        record(41.9028, 12.4964, after: 2, source: .manual)
        #expect(try count(Country.self) == 3)
        #expect(try count(GeoApp.City.self) == 3)
        let names = try context.fetch(FetchDescriptor<GeoApp.City>()).map(\.name).sorted()
        #expect(names == ["Berlin", "Paris", "Rome"])
    }

    @Test func flightIsIgnored() throws {
        #expect(record(50.0, 10.0, speed: 240) == .rejected(.flight))
        #expect(try count(Country.self) == 0)
    }

    @Test func inaccurateAndInvalidPositionsAreIgnored() throws {
        #expect(record(52.52, 13.405, accuracy: 12_000) == .rejected(.inaccurate))
        #expect(record(52.52, 13.405, accuracy: -1) == .rejected(.invalidAccuracy))
        #expect(try count(DayVisit.self) == 0)
    }

    @Test func openSeaStoresNothing() throws {
        #expect(record(30.0, -40.0) == .noCountry)
        #expect(try count(Country.self) == 0)
        #expect(try count(DayVisit.self) == 0)
    }

    @Test func countryWithoutCityCountsOnlyTheCountry() throws {
        #expect(record(25.0, 3.0) == .newDay(countryCode: "DZ", cityName: nil))
        #expect(record(25.1, 3.1, after: 1) == .sameDay(countryCode: "DZ", cityName: nil, count: 2))
        #expect(try count(Country.self) == 1)
        #expect(try count(GeoApp.City.self) == 0)
        #expect(try count(DayVisit.self) == 1)
    }

    @Test func diagnosticLogHasNoCoordinates() throws {
        record(48.8566, 2.3522)
        record(30.0, -40.0)
        let entries = try context.fetch(FetchDescriptor<DiagnosticEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(entries.count == 2)
        #expect(entries.first?.cityName == "Paris")
        #expect(entries.first?.outcome == "newDay")
        #expect(entries.last?.outcome == "noCountry")
    }

    /// Das Log hält weiter jede Erfassung fest, auch wenn nur ein Tageseintrag gespeichert ist.
    @Test func diagnosticLogCountsCapturesOfTheDay() throws {
        record(48.8566, 2.3522)
        record(48.8566, 2.3522, after: 1)
        let entries = try context.fetch(FetchDescriptor<DiagnosticEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(entries.map(\.outcome) == ["newDay", "sameDay:2"])
    }

    @Test func reducedAccuracyIsNotedInTheLog() throws {
        recorder.record(latitude: 48.8566, longitude: 2.3522, horizontalAccuracy: 3000, speed: -1,
                        timestamp: start, source: .significantChange, reducedAccuracy: true)
        let entry = try #require(try context.fetch(FetchDescriptor<DiagnosticEntry>()).first)
        #expect(entry.reducedAccuracy)
    }

    /// Ein gespeicherter Ort, den es in den Daten nicht mehr gibt (Stepney), wird zu London.
    /// Am selben Tag und im selben Gebiet werden die Einträge zusammengeführt.
    @Test func obsoleteCityIsRemappedToItsMetro() throws {
        record(51.5074, -0.1278, after: 1)  // London selbst
        let london = try #require(try visits().first)

        let stepney = GeoApp.City(
            from: GeoCore.City(id: 2636638, name: "Stepney", countryCode: "GB", latitude: 51.5152, longitude: -0.0462),
            visited: start)
        context.insert(stepney)
        DayVisits.add(DayVisits.Entry(day: london.day, countryCode: "GB", geonamesId: 2636638,
                                      regionId: london.regionId, districtId: london.districtId,
                                      timestamp: start, source: .significantChange), context: context)
        #expect(try count(DayVisit.self) == 2)

        CityRemapping.run(context: context)

        let cities = try context.fetch(FetchDescriptor<GeoApp.City>())
        #expect(cities.map(\.name) == ["London"])
        #expect(cities.first?.firstVisited == start)
        let merged = try visits()
        #expect(merged.count == 1)
        #expect(merged.first?.geonamesId == cities.first?.geonamesId)
        #expect(merged.first?.captureCount == 2)
        #expect(merged.first?.firstSeen == start)
    }

    /// London ist eine Zone: Wechsel zwischen Stadtteilen ergeben keinen neuen Eintrag.
    @Test func londonIsOneZone() throws {
        record(51.4995, -0.0195)            // Isle of Dogs
        #expect(record(51.4995, -0.1248, after: 1) == .sameDay(countryCode: "GB", cityName: "London", count: 2))

        let visits = try visits()
        #expect(visits.count == 1)
        let zone = try #require(visits.first?.districtId.flatMap { DistrictIndex.shared.district(id: $0) })
        #expect(zone.name == "London")

        let focus = CountryFocus.make(code: "GB", cities: try context.fetch(FetchDescriptor<GeoApp.City>()), visits: visits)
        #expect(focus.districtDays[zone.id] == 1)
    }

    @Test func diagnosticLogIsOffByDefault() throws {
        let silent = VisitRecorder(context: context, diagnosticsEnabled: { false })
        silent.record(latitude: 52.52, longitude: 13.405, horizontalAccuracy: 50, speed: -1,
                      timestamp: start, source: .manual)
        #expect(try count(DiagnosticEntry.self) == 0)
    }
}

/// Löschen einzelner Einträge und aller Daten.
@MainActor
struct DeletionTests {
    let container: ModelContainer
    let recorder: VisitRecorder
    var context: ModelContext { container.mainContext }
    let start = testDayStart

    init() throws {
        container = try Store.inMemory()
        recorder = VisitRecorder(context: container.mainContext, diagnosticsEnabled: { true })
        // Berlin, Hamburg, Paris
        for (lat, lon, hours) in [(52.52, 13.405, 0.0), (53.55, 9.99, 10.0), (48.8566, 2.3522, 20.0)] {
            recorder.record(latitude: lat, longitude: lon, horizontalAccuracy: 50, speed: -1,
                            timestamp: start.addingTimeInterval(hours * 3600), source: .significantChange)
        }
    }

    func names() throws -> [String] {
        try context.fetch(FetchDescriptor<GeoApp.City>()).map(\.name).sorted()
    }

    func codes() throws -> [String] {
        try context.fetch(FetchDescriptor<Country>()).map(\.isoCode).sorted()
    }

    @Test func deleteCityKeepsCountryWithOtherCities() throws {
        let hamburg = try #require(try context.fetch(FetchDescriptor<GeoApp.City>()).first { $0.name == "Hamburg" })
        try Deletion.deleteCity(hamburg.geonamesId, context: context)
        #expect(try names() == ["Berlin", "Paris"])
        #expect(try codes() == ["DE", "FR"])
        let germany = try #require(try context.fetch(FetchDescriptor<Country>()).first { $0.isoCode == "DE" })
        #expect(germany.lastVisited == start)  // Hamburg war der letzte Besuch in Deutschland
    }

    @Test func deleteLastCityRemovesCountry() throws {
        let paris = try #require(try context.fetch(FetchDescriptor<GeoApp.City>()).first { $0.name == "Paris" })
        try Deletion.deleteCity(paris.geonamesId, context: context)
        #expect(try codes() == ["DE"])
    }

    @Test func deleteCountryRemovesItsCitiesAndDays() throws {
        try Deletion.deleteCountry("DE", context: context)
        #expect(try names() == ["Paris"])
        #expect(try codes() == ["FR"])
        #expect(try context.fetchCount(FetchDescriptor<DayVisit>()) == 1)
    }

    @Test func deleteAllRemovesEverything() throws {
        try Deletion.deleteAll(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Country>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GeoApp.City>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<DayVisit>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<DiagnosticEntry>()) == 0)
    }
}

/// Gewichtung der Städte und Abstufung der Regionen in der Länderansicht.
@MainActor
struct CountryFocusTests {
    @Test func longStaysAndBigCitiesAreProminent() throws {
        let container = try Store.inMemory()
        let recorder = VisitRecorder(context: container.mainContext, diagnosticsEnabled: { false })
        let start = testDayStart
        func record(_ lat: Double, _ lon: Double, day: Double) {
            recorder.record(latitude: lat, longitude: lon, horizontalAccuracy: 50, speed: -1,
                            timestamp: start.addingTimeInterval(day * 86_400), source: .visit)
        }
        record(52.52, 13.405, day: 0)     // Berlin, zwei Tage
        record(52.52, 13.405, day: 1)
        record(52.392, 13.07, day: 2)     // Potsdam, ein Tag, ~180.000 Einwohner
        record(52.0897, 13.17, day: 3)    // Kleinstadt in Brandenburg, ein Tag

        let context = container.mainContext
        let focus = CountryFocus.make(code: "DE", cities: try context.fetch(FetchDescriptor<GeoApp.City>()),
                                      visits: try context.fetch(FetchDescriptor<DayVisit>()))
        let berlin = try #require(focus.pins.first { $0.name == "Berlin" })
        let potsdam = try #require(focus.pins.first { $0.name == "Potsdam" })
        let small = try #require(focus.pins.first { $0.name != "Berlin" && $0.name != "Potsdam" })

        #expect(berlin.days == 2 && berlin.isProminent)
        #expect(potsdam.days == 1 && potsdam.isProminent)      // groß genug
        #expect(small.population < 50_000 && !small.isProminent)
        #expect(focus.pins.first?.name == "Berlin")            // wichtigste zuerst

        let brandenburg = try #require(potsdam.regionId)
        #expect(focus.regionDays[brandenburg] == 2)            // Potsdam und Kleinstadt, zwei Tage
        #expect(CountryFocus.level(forDays: 0) == 0)
        #expect(CountryFocus.level(forDays: 1) == 1)
        #expect(CountryFocus.level(forDays: 3) == 2)
        #expect(CountryFocus.level(forDays: 10) == 3)
    }
}

/// Testdaten ein- und ausschalten: alle Szenarien vorhanden, echte Besuche bleiben unberührt.
@MainActor
struct MockDataTests {
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    private static let today = DayKey.today(now: now)

    /// Der Container muss so lange leben wie der Test, sonst stürzen Zugriffe auf seine Modelle ab.
    private let container: ModelContainer
    private let visits: [DayVisit]
    private let journal: Journal

    init() throws {
        container = try Store.inMemory()
        MockData.enable(context: container.mainContext, now: Self.now)
        visits = try container.mainContext.fetch(FetchDescriptor<DayVisit>())
        journal = Journal.make(visits: visits, homeOverride: nil, today: Self.today)
    }

    @Test func homeAndYears() throws {
        let munichRegion = try #require(GeoLookup.shared.cities.city(id: 2867714)?.regionId)
        #expect(journal.home == munichRegion)
        #expect(Set(visits.map { DayKey.year($0.day) }) == [2023, 2024, 2025, 2026])
        #expect(visits.allSatisfy { $0.isDemo })
        #expect(visits.allSatisfy { $0.day <= Self.today }, "Nichts in der Zukunft")
    }

    @Test func trips() throws {
        let trips = journal.trips
        #expect(trips.contains { Set($0.countryCodes).isSuperset(of: ["AT", "IT"]) }, "Mehrere Länder in einer Reise")
        #expect(trips.filter { $0.countryCodes.contains("IT") }.count >= 2, "Italien zweimal mit Pause")
        #expect(trips.contains { DayKey.year($0.startDay) != DayKey.year($0.endDay) }, "Reise über Silvester")
        #expect(trips.contains { $0.dayCount >= 10 }, "Lange Reise")
        #expect(trips.contains { $0.dayCount <= 3 && !$0.isOngoing && $0.cityIds.contains(2911298) }, "Kurze Reise (Hamburg)")
        #expect(trips.contains { $0.isOngoing }, "Laufende Reise")
        #expect(Set(trips.map { DayKey.year($0.startDay) }).isSuperset(of: [2023, 2024, 2025, 2026]))
    }

    /// Salzburg an einem Tag mit München morgens und abends: kein Teil einer Reise.
    @Test func dayTripIsNoTrip() throws {
        let salzburgDays = Set(visits.filter { $0.geonamesId == 2766824 }.map(\.day))
        #expect(salzburgDays.count == 1)
        let day = try #require(salzburgDays.first)
        #expect(visits.contains { $0.day == day && $0.geonamesId == 2867714 })
        #expect(!journal.trips.contains { $0.startDay <= day && day <= $0.endDay })
    }

    @Test func placesAndRegions() throws {
        let byDay = Dictionary(grouping: visits, by: \.day)
        #expect(byDay.values.contains { Set($0.compactMap(\.geonamesId)).count >= 2 }, "Mehrere Städte an einem Tag")
        #expect(visits.contains { $0.countryCode == "IS" && $0.geonamesId == nil }, "Tag nur mit Land")
        #expect(visits.contains { $0.countryCode == "RE" }, "Übersee")

        let munichRegion = try #require(GeoLookup.shared.cities.city(id: 2867714)?.regionId)
        let cities = try container.mainContext.fetch(FetchDescriptor<GeoApp.City>())
        let bavarian = cities.filter { GeoLookup.shared.cities.city(id: $0.geonamesId)?.regionId == munichRegion }
        #expect(bavarian.count >= 6, "Mehrere Städte in einer Region")
        let germanRegions = Set(visits.filter { $0.countryCode == "DE" }.compactMap(\.regionId))
        #expect(germanRegions.count >= 3, "Mehrere Regionen in Deutschland")
        #expect(Set(cities.map(\.countryCode)) == ["AT", "CH", "DE", "DK", "FR", "IS", "IT", "PT", "RE"])
    }

    /// Lissabon: ein Tag ohne Erfassung mitten in der Reise, den die Lückenfüllung schließt.
    @Test func gapDayIsFilled() throws {
        let recorded = Set(visits.filter { $0.countryCode == "PT" }.map(\.day))
        let inferred = journal.days.filter { $0.isInferred && $0.countryCode == "PT" }.map(\.day)
        #expect(inferred.contains { !recorded.contains($0) })
    }

    @Test func currentYearHasNewPlaces() throws {
        let stats = journal.statistics(year: 2026)
        #expect(stats.newCountryCodes.contains("DK"))
        #expect(stats.newCityIds.contains(2911298))   // Hamburg
        #expect(!stats.newCountryCodes.contains("DE"))
    }

    @Test func disableRestoresRealData() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        let real = Date(timeIntervalSince1970: 1_700_000_000)
        VisitRecorder(context: context, diagnosticsEnabled: { false })
            .record(latitude: 48.137, longitude: 11.575, horizontalAccuracy: 50, speed: -1,
                    timestamp: real, source: .visit)   // echter Besuch in München

        MockData.enable(context: context, now: Self.now)
        #expect(try context.fetchCount(FetchDescriptor<DayVisit>()) > 300)

        MockData.disable(context: context)
        let remaining = try context.fetch(FetchDescriptor<GeoApp.City>())
        #expect(remaining.map(\.name) == ["Munich"])
        #expect(remaining.first?.firstVisited == real)
        #expect(remaining.first?.lastVisited == real)
        #expect(try context.fetchCount(FetchDescriptor<DayVisit>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Country>()).map(\.isoCode) == ["DE"])
    }
}

/// Start: Diagnose-Log kürzen und Städte nur bei neuem Datenstand angleichen.
@MainActor
struct StoreTests {
    @Test func diagnosticLogIsPruned() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        let now = testDayStart
        // 20 alte Einträge und mehr frische, als das Log behalten soll.
        for day in 15..<35 {
            context.insert(DiagnosticEntry(timestamp: now.addingTimeInterval(-Double(day) * 86_400),
                                           source: .visit, outcome: "alt"))
        }
        for minute in 0..<(Store.diagnosticsMaxCount + 50) {
            context.insert(DiagnosticEntry(timestamp: now.addingTimeInterval(-Double(minute) * 60),
                                           source: .significantChange, outcome: "frisch"))
        }
        try context.save()

        Store.pruneDiagnostics(context: context, now: now)

        let entries = try context.fetch(FetchDescriptor<DiagnosticEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
        #expect(entries.count == Store.diagnosticsMaxCount)
        #expect(entries.allSatisfy { $0.outcome == "frisch" })
        #expect(entries.first?.timestamp == now)   // die neuesten bleiben
    }

    @Test func remappingRunsOnlyForANewDataVersion() async throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        let defaults = try #require(UserDefaults(suiteName: "StoreTests-\(UUID().uuidString)"))
        func insertStepney() {
            context.insert(GeoApp.City(
                from: GeoCore.City(id: 2636638, name: "Stepney", countryCode: "GB", latitude: 51.5152, longitude: -0.0462),
                visited: testDayStart))
        }
        func cityNames() throws -> [String] { try context.fetch(FetchDescriptor<GeoApp.City>()).map(\.name) }

        // Gleicher Datenstand: nichts zu tun, auch eine veraltete Stadt bleibt.
        defaults.set(GeoLookup.dataVersion, forKey: AppSettings.dataVersion)
        insertStepney()
        await Store.bootstrap(context: context, defaults: defaults)
        #expect(try cityNames() == ["Stepney"])

        // Neuer Datenstand: Stepney wird zu London, danach ist der Stand gemerkt.
        defaults.set("älter", forKey: AppSettings.dataVersion)
        await Store.bootstrap(context: context, defaults: defaults)
        #expect(try cityNames() == ["London"])
        #expect(defaults.string(forKey: AppSettings.dataVersion) == GeoLookup.dataVersion)
    }
}

/// Ein Speicher aus der Zeit vor den Tageseinträgen wird beim Öffnen umgestellt, ohne Daten zu verlieren.
@MainActor
struct MigrationTests {
    private func makeV1Store(at url: URL, start: Date) throws {
        // Wie die App bis V1 den Speicher angelegt hat: ohne Versionsangabe.
        let schema = Schema([SchemaV1.Country.self, SchemaV1.City.self, SchemaV1.VisitEvent.self, SchemaV1.DiagnosticEntry.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        context.insert(SchemaV1.Country(isoCode: "DE", name: "Germany", visited: start))
        context.insert(SchemaV1.Country(isoCode: "FR", name: "France", visited: start))
        context.insert(SchemaV1.City(geonamesId: 2950159, name: "Berlin", countryCode: "DE",
                                     centerLatitude: 52.524, centerLongitude: 13.411, visited: start))
        context.insert(SchemaV1.City(geonamesId: 2988507, name: "Paris", countryCode: "FR",
                                     centerLatitude: 48.853, centerLongitude: 2.349, visited: start))
        // Berlin dreimal am selben Tag (zwei Quellen), einmal am nächsten Tag, Paris einmal.
        for (hours, id, code, source) in [(0.0, 2950159, "DE", CaptureSource.significantChange),
                                          (6.5, 2950159, "DE", .significantChange),
                                          (13.0, 2950159, "DE", .visit),
                                          (25.0, 2950159, "DE", .visit),
                                          (2.0, 2988507, "FR", .manual)] {
            context.insert(SchemaV1.VisitEvent(timestamp: start.addingTimeInterval(hours * 3600), geonamesId: id,
                                               countryCode: code, source: source, districtId: "\(code):1"))
        }
        try context.save()
    }

    @Test func visitEventsBecomeDays() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")
        let start = testDayStart
        try makeV1Store(at: url, start: start)

        let container = try ModelContainer(for: Store.schema, migrationPlan: GeoMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: Store.schema, url: url))
        let context = container.mainContext

        let visits = try context.fetch(FetchDescriptor<DayVisit>(sortBy: [SortDescriptor(\.day), SortDescriptor(\.countryCode)]))
        #expect(visits.count == 3)
        let berlinFirstDay = try #require(visits.first { $0.geonamesId == 2950159 && $0.captureCount == 3 })
        #expect(berlinFirstDay.firstSeen == start)
        #expect(berlinFirstDay.lastSeen == start.addingTimeInterval(13 * 3600))
        #expect(berlinFirstDay.sources == [.significantChange, .visit])
        #expect(berlinFirstDay.districtId == "DE:1")
        #expect(visits.contains { $0.geonamesId == 2950159 && $0.captureCount == 1 && $0.day != berlinFirstDay.day })
        #expect(visits.contains { $0.geonamesId == 2988507 && $0.sources == [.manual] })

        #expect(try context.fetch(FetchDescriptor<Country>()).map(\.isoCode).sorted() == ["DE", "FR"])
        #expect(try context.fetch(FetchDescriptor<GeoApp.City>()).map(\.name).sorted() == ["Berlin", "Paris"])
    }
}

/// Datenschutz-Prüfung: Kein gespeichertes Feld darf die Position der Person halten.
struct PrivacyTests {
    @Test func noModelStoresRawCoordinates() {
        // Erlaubt ist nur die Stadtmitte aus GeoNames.
        let allowed: Set<String> = ["City.centerLatitude", "City.centerLongitude"]
        for entity in Store.schema.entities {
            for attribute in entity.attributes {
                let name = attribute.name.lowercased()
                let looksLikeCoordinate = ["lat", "lon", "coordinate", "location", "position"].contains { name.contains($0) }
                if looksLikeCoordinate {
                    #expect(allowed.contains("\(entity.name).\(attribute.name)"),
                            "Verdächtiges Feld: \(entity.name).\(attribute.name)")
                }
            }
        }
    }

    /// Was die App Group für die Widgets ablegt (Snapshot, D8) enthält keine Position, weder im Text noch als Schlüssel.
    @Test func appGroupFilesHaveNoCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivacyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = WidgetSnapshot.url(in: directory)
        try WidgetSnapshot.placeholder.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.lowercased().contains("latitude"), "Snapshot enthält \"latitude\"")
        #expect(!text.lowercased().contains("longitude"), "Snapshot enthält \"longitude\"")

        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let object = try #require(parsed as? [String: Any])
        let coordinateKeys = object.keys.filter(WidgetSnapshotTests.isCoordinateKey)
        #expect(coordinateKeys.isEmpty, "Verdächtige Schlüssel im Snapshot: \(coordinateKeys.joined(separator: ", "))")
    }
}
