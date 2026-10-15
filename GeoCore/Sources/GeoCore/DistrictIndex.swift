import Foundation

/// Ein Kreis: die Ebene unter den Regionen (Landkreis, Département, County, Bezirk).
public struct District: Sendable, Identifiable {
    public let id: String
    public let regionId: String
    public let name: String
    public let polygons: [Polygon]
    public let bbox: BoundingBox
}

/// Kreise aus `Districts/<Land>.json.z` (siehe tools/build_districts.py).
///
/// Jedes Land liegt in einer eigenen Datei und wird erst geladen, wenn man in dieses Land
/// hineinzoomt. Danach bleibt es im Speicher.
public final class DistrictIndex: @unchecked Sendable {
    public static let shared = DistrictIndex(bundle: .module)

    /// Herkunft und Lizenz der Kreisdaten eines Landes, für die Lizenzseite.
    public struct Source: Decodable, Sendable {
        public let cc: String
        public let source: String
        public let license: String
    }

    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [String: [District]] = [:]

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// Kreise eines Landes, leer für Länder ohne Kreise.
    public func districts(in countryCode: String) -> [District] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[countryCode] { return cached }
        let districts = load(countryCode)
        cache[countryCode] = districts
        return districts
    }

    public func districts(inRegion regionId: String, countryCode: String) -> [District] {
        districts(in: countryCode).filter { $0.regionId == regionId }
    }

    /// Kreis, in dem der Punkt liegt.
    public func district(in countryCode: String, lat: Double, lon: Double) -> District? {
        districts(in: countryCode).first { district in
            district.bbox.contains(lat: lat, lon: lon) && district.polygons.contains { $0.contains(lat: lat, lon: lon) }
        }
    }

    public func district(id: String) -> District? {
        guard let countryCode = id.split(separator: ":").first else { return nil }
        return districts(in: String(countryCode)).first { $0.id == id }
    }

    public var sources: [Source] {
        guard let url = bundle.url(forResource: "_sources", withExtension: "json", subdirectory: "Districts"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Source].self, from: data)) ?? []
    }

    private struct File: Decodable {
        struct Entry: Decodable {
            let id: String
            let region: String
            let name: String
            let polygons: [[[Double]]]
        }
        let districts: [Entry]
    }

    private func load(_ countryCode: String) -> [District] {
        guard let url = bundle.url(forResource: "\(countryCode).json", withExtension: "z", subdirectory: "Districts"),
              let data = try? inflate(Data(contentsOf: url)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.districts.compactMap { entry in
            let polygons = entry.polygons.map(Polygon.init(rings:))
            guard let first = polygons.first else { return nil }
            let bbox = polygons.dropFirst().reduce(first.bbox) { $0.union($1.bbox) }
            return District(id: entry.id, regionId: entry.region, name: entry.name, polygons: polygons, bbox: bbox)
        }
    }
}
