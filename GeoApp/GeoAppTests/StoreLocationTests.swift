import Foundation
import GeoCore
import SwiftData
import Testing
@testable import GeoApp

/// Umzug des Speichers in die App Group (D7), mit echten Dateien in einem temporären Ordner.
@MainActor
struct StoreLocationTests {
    private let visitTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "StoreLocationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Alter Speicher: `old/default.store`.
    private func legacyURL(in dir: URL) -> URL {
        dir.appending(path: "old/default.store")
    }

    /// Ordner der App Group in der Testumgebung.
    private func groupFolder(in dir: URL) -> URL {
        dir.appending(path: "group")
    }

    private func destinationStore(in group: URL) -> URL {
        group.appending(path: "Library/Application Support/GeoApp.store")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func fileNames(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func storeFileNames(in folder: URL) -> [String] {
        fileNames(in: folder).filter { $0.hasPrefix("GeoApp.store") }
    }

    private func isFailed(_ outcome: StoreLocation.Outcome) -> Bool {
        if case .failed = outcome { return true }
        return false
    }

    /// Legt einen echten Speicher mit einem Land und zwei Tageseinträgen an. Der Container
    /// verlässt den Gültigkeitsbereich mit der Funktion, danach ist die Datei frei.
    private func makeRealStore(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try ModelContainer(for: Store.schema, migrationPlan: GeoMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: Store.schema, url: url))
        let context = container.mainContext
        context.insert(Country(isoCode: "DE", name: "Germany", visited: visitTime))
        for day in [20260512, 20260513] {
            DayVisits.add(DayVisits.Entry(day: day, countryCode: "DE", geonamesId: 2950159, regionId: "DE-BY",
                                          districtId: nil, timestamp: visitTime, source: .significantChange),
                          context: context)
        }
        try context.save()
    }

    @Test func freshInstall() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let destination = destinationStore(in: groupFolder(in: dir))

        #expect(StoreLocation.migrate(from: legacy, to: destination) == .freshInstall)
        #expect(storeFileNames(in: destination.deletingLastPathComponent()).isEmpty)
    }

    @Test func movesRealStore() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let destination = destinationStore(in: groupFolder(in: dir))
        try makeRealStore(at: legacy)

        #expect(StoreLocation.migrate(from: legacy, to: destination) == .moved)

        let container = try ModelContainer(for: Store.schema, migrationPlan: GeoMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: Store.schema, url: destination))
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<Country>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DayVisit>()) == 2)
        #expect(exists(legacy))
    }

    @Test func copiesSidecars() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        try write("main", to: legacy)
        try write("wal", to: legacy.deletingLastPathComponent().appending(path: "default.store-wal"))
        try write("shm", to: legacy.deletingLastPathComponent().appending(path: "default.store-shm"))
        let destination = destinationStore(in: groupFolder(in: dir))

        #expect(StoreLocation.migrate(from: legacy, to: destination) == .moved)

        let folder = destination.deletingLastPathComponent()
        #expect(fileNames(in: folder) == ["GeoApp.store", "GeoApp.store-shm", "GeoApp.store-wal"])
        #expect(read(destination) == "main")
        #expect(read(folder.appending(path: "GeoApp.store-wal")) == "wal")
        #expect(read(folder.appending(path: "GeoApp.store-shm")) == "shm")
    }

    @Test func alreadyMovedDoesNothing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let destination = destinationStore(in: groupFolder(in: dir))
        try write("old", to: legacy)
        try write("new", to: destination)

        #expect(StoreLocation.migrate(from: legacy, to: destination) == .alreadyMoved)
        #expect(read(destination) == "new")
        #expect(read(legacy) == "old")
    }

    @Test func interruptedMoveIsRedone() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        try write("main", to: legacy)
        let destination = destinationStore(in: groupFolder(in: dir))
        let folder = destination.deletingLastPathComponent()
        try write("stale", to: folder.appending(path: "GeoApp.store-wal"))
        try write("partial", to: folder.appending(path: "GeoApp.store.moving"))

        #expect(StoreLocation.migrate(from: legacy, to: destination) == .moved)
        #expect(read(destination) == "main")
        #expect(!exists(folder.appending(path: "GeoApp.store-wal")))
        #expect(!exists(folder.appending(path: "GeoApp.store.moving")))
    }

    @Test func resolveWithoutGroup() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let group = groupFolder(in: dir)
        let destination = destinationStore(in: group)

        let without = StoreLocation.resolve(legacy: legacy, group: nil)
        #expect(without.url == legacy)
        #expect(without.outcome == .unavailable)

        #expect(StoreLocation.destination(inGroup: group) == destination)
        let with = StoreLocation.resolve(legacy: legacy, group: group)
        #expect(with.url == destination)
        #expect(with.outcome == .freshInstall)
    }

    @Test func removeLegacy() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let folder = legacy.deletingLastPathComponent()
        try write("main", to: legacy)
        try write("wal", to: folder.appending(path: "default.store-wal"))
        try write("shm", to: folder.appending(path: "default.store-shm"))
        try write("keep", to: folder.appending(path: "other.txt"))

        StoreLocation.removeLegacy(at: legacy)
        #expect(!exists(legacy))
        #expect(!exists(folder.appending(path: "default.store-wal")))
        #expect(!exists(folder.appending(path: "default.store-shm")))
        #expect(read(folder.appending(path: "other.txt")) == "keep")

        // Zweiter Aufruf, die Dateien fehlen: kein Fehler.
        StoreLocation.removeLegacy(at: legacy)
        #expect(read(folder.appending(path: "other.txt")) == "keep")
    }

    @Test func failedCopyKeepsLegacy() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        try write("main", to: legacy)
        let group = groupFolder(in: dir)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        // `Library` ist eine Datei, der Zielordner lässt sich nicht anlegen.
        FileManager.default.createFile(atPath: group.appending(path: "Library").path, contents: Data("x".utf8))
        let destination = destinationStore(in: group)

        #expect(isFailed(StoreLocation.migrate(from: legacy, to: destination)))

        let resolved = StoreLocation.resolve(legacy: legacy, group: group)
        #expect(resolved.url == legacy)
        #expect(isFailed(resolved.outcome))
        #expect(read(legacy) == "main")
    }

    @Test func openAfterMoveDeletesLegacy() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        let group = groupFolder(in: dir)
        let destination = destinationStore(in: group)
        try makeRealStore(at: legacy)

        do {
            let first = try Store.makeContainer(legacy: legacy, group: group)
            #expect(first.url == destination)
            #expect(first.outcome == .moved)
            #expect(try first.container.mainContext.fetchCount(FetchDescriptor<DayVisit>()) == 2)
        }
        #expect(!exists(legacy))

        do {
            let second = try Store.makeContainer(legacy: legacy, group: group)
            #expect(second.url == destination)
            #expect(second.outcome == .alreadyMoved)
            #expect(try second.container.mainContext.fetchCount(FetchDescriptor<DayVisit>()) == 2)
        }
    }

    @Test func corruptCopyFallsBack() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = legacyURL(in: dir)
        try write("not a database", to: legacy)
        let group = groupFolder(in: dir)
        let destination = destinationStore(in: group)

        var threw = false
        do {
            _ = try Store.makeContainer(legacy: legacy, group: group)
        } catch {
            threw = true
        }
        #expect(threw)
        #expect(!exists(destination))
        #expect(read(legacy) == "not a database")
    }

    @Test func appGroupEntitlements() throws {
        // Diese Datei liegt in GeoApp/GeoAppTests/, die Projektdateien in GeoApp/.
        let projectFolder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appEntitlements = try String(contentsOf: projectFolder.appending(path: "GeoApp.entitlements"), encoding: .utf8)
        let widgetEntitlements = try String(contentsOf: projectFolder.appending(path: "GeoWidgets/GeoWidgets.entitlements"),
                                            encoding: .utf8)
        let project = try String(contentsOf: projectFolder.appending(path: "GeoApp.xcodeproj/project.pbxproj"),
                                 encoding: .utf8)

        for entitlements in [appEntitlements, widgetEntitlements] {
            #expect(entitlements.contains("com.apple.security.application-groups"))
            #expect(entitlements.contains("group.de.max.geoapp"))
        }
        #expect(project.contains("CODE_SIGN_ENTITLEMENTS = GeoApp.entitlements"))
        #expect(project.contains("CODE_SIGN_ENTITLEMENTS = GeoWidgets/GeoWidgets.entitlements"))
        #expect(StoreLocation.appGroupID == "group.de.max.geoapp")
    }
}
