import Foundation

/// Eine Region innerhalb eines Landes (Bundesland, Staat, Provinz oder eine Gruppe davon).
public struct Region: Sendable, Identifiable {
    public let id: String
    public let countryCode: String
    public let name: String
    public let polygons: [Polygon]
    public let bbox: BoundingBox
}

/// Regionen für die Länderansicht aus `regions.json.z` (Natural Earth Admin-1, siehe tools/build_regions.py).
///
/// Wird nur für die Karte gebraucht und deshalb getrennt von `GeoLookup` und erst beim ersten
/// Zugriff geladen, damit die Erfassung im Hintergrund schnell bleibt.
public struct RegionIndex: Sendable {
    public static let shared: RegionIndex = {
        guard let url = Bundle.module.url(forResource: "regions.json", withExtension: "z"),
              let data = try? inflate(Data(contentsOf: url)),
              let index = try? RegionIndex(jsonData: data) else {
            return RegionIndex(regions: [])
        }
        return index
    }()

    private let byCountry: [String: [Region]]
    private let byID: [String: Region]

    public init(regions: [Region]) {
        byCountry = Dictionary(grouping: regions, by: \.countryCode)
        byID = Dictionary(regions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Regionen eines Landes, leer für kleine Länder ohne Unterteilung.
    public func regions(in countryCode: String) -> [Region] {
        byCountry[countryCode] ?? []
    }

    public func region(id: String) -> Region? {
        byID[id]
    }

    /// Region eines Landes, in der der Punkt liegt (etwa für einen Tipp auf die Karte).
    public func region(in countryCode: String, lat: Double, lon: Double) -> Region? {
        regions(in: countryCode).first { region in
            region.bbox.contains(lat: lat, lon: lon) && region.polygons.contains { $0.contains(lat: lat, lon: lon) }
        }
    }
}

extension RegionIndex {
    private struct File: Decodable {
        struct Entry: Decodable {
            let id: String
            let cc: String
            let name: String
            let polygons: [[[Double]]]
        }
        let regions: [Entry]
    }

    public init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        let regions = file.regions.compactMap { entry -> Region? in
            let polygons = entry.polygons.map(Polygon.init(rings:))
            guard let first = polygons.first else { return nil }
            let bbox = polygons.dropFirst().reduce(first.bbox) { $0.union($1.bbox) }
            return Region(id: entry.id, countryCode: entry.cc, name: entry.name, polygons: polygons, bbox: bbox)
        }
        self.init(regions: regions)
    }
}

/// Entpackt rohes Deflate, wie es `tools/build_districts.py` schreibt.
func inflate(_ data: Data) throws -> Data {
    try (data as NSData).decompressed(using: .zlib) as Data
}
