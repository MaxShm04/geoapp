import Foundation

/// Eine Linie als flache Liste [lon, lat, lon, lat, ...].
public struct Polyline: Sendable {
    public let points: [Double]
    public let bbox: BoundingBox

    init(points: [Double]) {
        self.points = points
        self.bbox = BoundingBox(flatRing: points)
    }
}

/// Wasserflächen, Parks und Hauptstraßen einer Großstadt aus OpenStreetMap
/// (`CityDetail/<geonameid>.json.z`, siehe tools/build_citydetail.py). © OpenStreetMap-Mitwirkende, ODbL.
public struct CityDetail: Sendable {
    public enum RoadClass: Int, Sendable {
        case motorway = 0, trunk = 1, primary = 2
    }

    public struct Road: Sendable {
        public let roadClass: RoadClass
        public let line: Polyline
    }

    public let cityID: Int
    public let bbox: BoundingBox
    public let water: [Polygon]
    public let parks: [Polygon]
    public let roads: [Road]
}

/// Welche Großstädte Details haben, und die Details selbst, erst bei Bedarf geladen.
public final class CityDetailIndex: @unchecked Sendable {
    public static let shared = CityDetailIndex(bundle: .module)

    private struct Entry: Decodable {
        let id: String
        let bbox: [Double]
    }

    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [Int: CityDetail] = [:]
    /// Städte mit Details und ihr Ausschnitt.
    public let areas: [(cityID: Int, bbox: BoundingBox)]

    init(bundle: Bundle) {
        self.bundle = bundle
        let entries: [Entry] = bundle.url(forResource: "_index", withExtension: "json", subdirectory: "CityDetail")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        areas = entries.compactMap { entry in
            guard let id = Int(entry.id), entry.bbox.count == 4 else { return nil }
            return (id, BoundingBox(minLat: entry.bbox[1], minLon: entry.bbox[0], maxLat: entry.bbox[3], maxLon: entry.bbox[2]))
        }
    }

    /// Städte mit Details, deren Ausschnitt den sichtbaren Bereich berührt.
    public func cities(intersecting visible: BoundingBox) -> [Int] {
        areas.filter { area in
            area.bbox.minLat <= visible.maxLat && area.bbox.maxLat >= visible.minLat
                && area.bbox.minLon <= visible.maxLon && area.bbox.maxLon >= visible.minLon
        }.map(\.cityID)
    }

    public func detail(for cityID: Int) -> CityDetail? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[cityID] { return cached }
        guard let detail = load(cityID) else { return nil }
        cache[cityID] = detail
        return detail
    }

    private struct File: Decodable {
        struct RoadEntry: Decodable { let c: Int; let l: [Double] }
        let bbox: [Double]
        let water: [[[Double]]]
        let parks: [[[Double]]]
        let roads: [RoadEntry]
    }

    private func load(_ cityID: Int) -> CityDetail? {
        guard let url = bundle.url(forResource: "\(cityID).json", withExtension: "z", subdirectory: "CityDetail"),
              let data = try? inflate(Data(contentsOf: url)),
              let file = try? JSONDecoder().decode(File.self, from: data), file.bbox.count == 4 else { return nil }
        return CityDetail(
            cityID: cityID,
            bbox: BoundingBox(minLat: file.bbox[1], minLon: file.bbox[0], maxLat: file.bbox[3], maxLon: file.bbox[2]),
            water: file.water.map(Polygon.init(rings:)),
            parks: file.parks.map(Polygon.init(rings:)),
            roads: file.roads.map { CityDetail.Road(roadClass: CityDetail.RoadClass(rawValue: $0.c) ?? .primary, line: Polyline(points: $0.l)) })
    }
}
