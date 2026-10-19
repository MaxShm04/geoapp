import Foundation

/// Umzug des Speichers in die App Group (Entscheidung D7). Einmalig beim ersten Start nach dem
/// Update, bevor der Speicher geöffnet wird.
///
/// Ablauf: Die Dateien des alten Speichers werden unter einem Zwischennamen kopiert und dann an
/// ihren Platz umbenannt, die Hauptdatei zuletzt. Ob der Umzug fertig ist, entscheidet allein die
/// Hauptdatei am neuen Ort. Der alte Speicher wird erst gelöscht, wenn die Kopie geöffnet ist
/// (`Store.makeContainer`). So liegt zu jedem Zeitpunkt ein vollständiger Speicher vor.
nonisolated enum StoreLocation {
    static let appGroupID = AppGroup.identifier
    static let fileName = "GeoApp.store"
    /// Endung der Zwischenkopie, bevor sie an ihren Platz umbenannt wird.
    private static let stagingSuffix = ".moving"
    /// Begleitdateien von SQLite im WAL-Modus.
    private static let sidecarSuffixes = ["-wal", "-shm"]

    enum Outcome: Equatable, Sendable {
        /// Weder alter noch neuer Speicher, die App legt einen neuen an.
        case freshInstall
        /// Der Speicher liegt schon in der App Group.
        case alreadyMoved
        /// Der alte Speicher wurde gerade in die App Group kopiert.
        case moved
        /// Keine App Group, die App bleibt beim alten Ort.
        case unavailable
        /// Kopieren fehlgeschlagen, die App bleibt beim alten Ort.
        case failed(String)
    }

    /// Bisheriger Ort: `Application Support/default.store` (Standard von SwiftData).
    static var legacyURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Neuer Ort in der App Group, `nil` ohne App Group.
    static var groupURL: URL? {
        AppGroup.containerURL.map(destination(inGroup:))
    }

    /// `<group>/Library/Application Support/GeoApp.store`
    static func destination(inGroup container: URL) -> URL {
        container.appending(path: "Library/Application Support/\(fileName)")
    }

    /// Hauptdatei und die SQLite-Begleitdateien `-wal` und `-shm`.
    static func storeFiles(of url: URL) -> [URL] {
        [url] + sidecarSuffixes.map { url.deletingLastPathComponent().appending(path: url.lastPathComponent + $0) }
    }

    /// Kopiert den alten Speicher, falls nötig. Löscht den alten Speicher nie.
    static func migrate(from legacy: URL, to destination: URL, fileManager: FileManager = .default) -> Outcome {
        if fileManager.fileExists(atPath: destination.path) { return .alreadyMoved }
        guard fileManager.fileExists(atPath: legacy.path) else { return .freshInstall }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let sources = storeFiles(of: legacy)
            let targets = storeFiles(of: destination)
            // Reste eines abgebrochenen Umzugs entfernen: Begleitdateien ohne Hauptdatei, Zwischenkopien.
            for target in targets {
                try removeIfPresent(target, fileManager: fileManager)
                try removeIfPresent(staging(target), fileManager: fileManager)
            }
            // Erst alles unter Zwischennamen kopieren, dann umbenennen, die Hauptdatei zuletzt.
            var copied: [URL] = []
            for (source, target) in zip(sources, targets) where fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: staging(target))
                copied.append(target)
            }
            for target in copied.reversed() {
                try fileManager.moveItem(at: staging(target), to: target)
            }
            return .moved
        } catch {
            for target in storeFiles(of: destination) {
                try? removeIfPresent(staging(target), fileManager: fileManager)
            }
            // Ohne Hauptdatei gilt der Umzug als nicht geschehen; halbe Begleitdateien entfernen.
            if !fileManager.fileExists(atPath: destination.path) {
                for target in storeFiles(of: destination) { try? removeIfPresent(target, fileManager: fileManager) }
            }
            return .failed(error.localizedDescription)
        }
    }

    /// Welcher Ort geöffnet wird: die App Group, sonst (ohne App Group oder nach einem Fehler) der alte.
    static func resolve(legacy: URL, group: URL?, fileManager: FileManager = .default) -> (url: URL, outcome: Outcome) {
        guard let group else { return (legacy, .unavailable) }
        let destination = destination(inGroup: group)
        let outcome = migrate(from: legacy, to: destination, fileManager: fileManager)
        if case .failed = outcome { return (legacy, outcome) }
        return (destination, outcome)
    }

    /// Löscht den alten Speicher, nachdem die Kopie erfolgreich geöffnet wurde. Fehlende Dateien sind kein Fehler.
    static func removeLegacy(at legacy: URL, fileManager: FileManager = .default) {
        for file in storeFiles(of: legacy) {
            try? removeIfPresent(file, fileManager: fileManager)
        }
    }

    /// Entfernt die Kopie in der App Group, etwa wenn sie sich nicht öffnen ließ.
    static func removeStore(at url: URL, fileManager: FileManager = .default) {
        removeLegacy(at: url, fileManager: fileManager)
    }

    private static func staging(_ url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + stagingSuffix)
    }

    private static func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }
}
