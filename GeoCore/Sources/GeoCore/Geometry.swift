import Foundation

/// Achsenparalleles Rechteck in Grad.
public struct BoundingBox: Sendable, Hashable {
    public var minLat: Double
    public var minLon: Double
    public var maxLat: Double
    public var maxLon: Double

    init(flatRing: [Double]) {
        var box = BoundingBox(minLat: .infinity, minLon: .infinity, maxLat: -.infinity, maxLon: -.infinity)
        var i = 0
        while i + 1 < flatRing.count {
            box.minLon = min(box.minLon, flatRing[i])
            box.maxLon = max(box.maxLon, flatRing[i])
            box.minLat = min(box.minLat, flatRing[i + 1])
            box.maxLat = max(box.maxLat, flatRing[i + 1])
            i += 2
        }
        self = box
    }

    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    public var area: Double { (maxLat - minLat) * (maxLon - minLon) }

    func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(minLat: min(minLat, other.minLat), minLon: min(minLon, other.minLon),
                    maxLat: max(maxLat, other.maxLat), maxLon: max(maxLon, other.maxLon))
    }

    func contains(lat: Double, lon: Double, marginKm: Double = 0) -> Bool {
        let dLat = marginKm / 110.574
        let dLon = marginKm / max(111.320 * cos(lat * .pi / 180), 1)
        return lat >= minLat - dLat && lat <= maxLat + dLat && lon >= minLon - dLon && lon <= maxLon + dLon
    }
}

/// Ein Polygon aus Ringen als flache Listen [lon, lat, lon, lat, ...].
/// Der erste Ring ist die Außengrenze, weitere Ringe sind Löcher (etwa Lesotho in Südafrika).
public struct Polygon: Sendable {
    public let rings: [[Double]]
    public let bbox: BoundingBox

    init(rings: [[Double]]) {
        self.rings = rings
        self.bbox = BoundingBox(flatRing: rings.first ?? [])
    }

    /// Ray-Casting mit Gerade-Ungerade-Regel über alle Ringe, damit zählen Löcher automatisch nicht dazu.
    func contains(lat: Double, lon: Double) -> Bool {
        guard bbox.contains(lat: lat, lon: lon) else { return false }
        var inside = false
        for ring in rings {
            let n = ring.count / 2
            guard n >= 3 else { continue }
            var j = n - 1
            for i in 0..<n {
                let xi = ring[2 * i], yi = ring[2 * i + 1]
                let xj = ring[2 * j], yj = ring[2 * j + 1]
                if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }

    /// Kürzeste Entfernung in km vom Punkt zu einer Kante. Lokale flache Projektion,
    /// genau genug für die wenigen Kilometer der Küstentoleranz.
    func distanceToEdgeKm(lat: Double, lon: Double) -> Double {
        let kx = 111.320 * cos(lat * .pi / 180)
        let ky = 110.574
        var best = Double.infinity
        for ring in rings {
            let n = ring.count / 2
            guard n >= 2 else { continue }
            var ax = (ring[0] - lon) * kx, ay = (ring[1] - lat) * ky
            for i in 1..<n {
                let bx = (ring[2 * i] - lon) * kx, by = (ring[2 * i + 1] - lat) * ky
                best = min(best, segmentDistance(ax, ay, bx, by))
                ax = bx
                ay = by
            }
        }
        return best
    }
}

/// Abstand des Ursprungs zur Strecke A–B.
private func segmentDistance(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let dx = bx - ax, dy = by - ay
    let lengthSquared = dx * dx + dy * dy
    var t = lengthSquared > 0 ? -(ax * dx + ay * dy) / lengthSquared : 0
    t = min(max(t, 0), 1)
    let px = ax + t * dx, py = ay + t * dy
    return (px * px + py * py).squareRoot()
}

/// Großkreisentfernung in km.
public func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
    let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
    let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
    return 2 * 6371.0 * asin(min(1, a.squareRoot()))
}
