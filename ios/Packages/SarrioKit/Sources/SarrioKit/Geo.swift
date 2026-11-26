import Foundation

/// Punto de un track GPS.
public struct TrackPoint: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double
    /// Altitud en metros (puede faltar en algunos archivos).
    public var elevation: Double?
    public var time: Date?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }
}

public struct BoundingBox: Sendable, Hashable, Codable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init?(points: some Collection<TrackPoint>) {
        guard let first = points.first else { return nil }
        var box = (first.latitude, first.longitude, first.latitude, first.longitude)
        for p in points {
            box.0 = min(box.0, p.latitude); box.1 = min(box.1, p.longitude)
            box.2 = max(box.2, p.latitude); box.3 = max(box.3, p.longitude)
        }
        (minLatitude, minLongitude, maxLatitude, maxLongitude) = box
    }

    /// Amplía la caja `meters` metros en cada dirección.
    public func expanded(byMeters meters: Double) -> BoundingBox {
        let dLat = meters / 111_320
        let midLat = (minLatitude + maxLatitude) / 2
        let dLon = meters / (111_320 * max(cos(midLat * .pi / 180), 0.01))
        var copy = self
        copy.minLatitude -= dLat; copy.maxLatitude += dLat
        copy.minLongitude -= dLon; copy.maxLongitude += dLon
        return copy
    }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        (minLatitude...maxLatitude).contains(latitude) && (minLongitude...maxLongitude).contains(longitude)
    }
}

public enum Geo {
    public static let earthRadius = 6_371_008.8

    /// Distancia ortodrómica en metros.
    public static func distance(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let r = Double.pi / 180
        let dLat = (bLat - aLat) * r
        let dLon = (bLon - aLon) * r
        let h = pow(sin(dLat / 2), 2) + cos(aLat * r) * cos(bLat * r) * pow(sin(dLon / 2), 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    public static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        distance(a.latitude, a.longitude, b.latitude, b.longitude)
    }

    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Geohash compatible con el backend (`backend/src/lib/geo.ts`).
    public static func geohash(latitude: Double, longitude: Double, precision: Int = 5) -> String {
        var lat = (-90.0, 90.0), lon = (-180.0, 180.0)
        var hash = "", bit = 0, ch = 0, even = true
        while hash.count < precision {
            if even {
                let mid = (lon.0 + lon.1) / 2
                if longitude >= mid { ch = (ch << 1) | 1; lon.0 = mid } else { ch <<= 1; lon.1 = mid }
            } else {
                let mid = (lat.0 + lat.1) / 2
                if latitude >= mid { ch = (ch << 1) | 1; lat.0 = mid } else { ch <<= 1; lat.1 = mid }
            }
            even.toggle()
            bit += 1
            if bit == 5 { hash.append(base32[ch]); bit = 0; ch = 0 }
        }
        return hash
    }

    /// Celdas geohash de `precision` caracteres que cubren la caja (muestreo en rejilla).
    public static func geohashCells(covering box: BoundingBox, precision: Int = 4) -> Set<String> {
        // Una celda de precisión 4 mide ~0,176º × 0,176º en el peor caso; muestreamos más fino.
        let step = 0.08
        var cells = Set<String>()
        var lat = box.minLatitude
        while lat <= box.maxLatitude + step {
            var lon = box.minLongitude
            while lon <= box.maxLongitude + step {
                cells.insert(geohash(latitude: min(lat, box.maxLatitude), longitude: min(lon, box.maxLongitude), precision: precision))
                lon += step
            }
            lat += step
        }
        return cells
    }

    /// Simplificación Douglas-Peucker (tolerancia en metros, aproximación equirectangular local).
    /// Los índices de `keeping` se conservan siempre (p. ej. los puntos más cercanos a cada cumbre).
    public static func simplify(_ points: [TrackPoint], tolerance: Double, keeping: Set<Int> = []) -> [TrackPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        let anchors = ([0, points.count - 1] + keeping.filter { points.indices.contains($0) }).sorted()
        for i in anchors { keep[i] = true }
        var stack: [(Int, Int)] = zip(anchors, anchors.dropFirst()).filter { $1 - $0 > 1 }.map { ($0, $1) }
        while let (start, end) = stack.popLast() {
            var maxDist = 0.0, index = start
            for i in (start + 1)..<end {
                let d = perpendicularDistance(points[i], points[start], points[end])
                if d > maxDist { maxDist = d; index = i }
            }
            if maxDist > tolerance {
                keep[index] = true
                if index - start > 1 { stack.append((start, index)) }
                if end - index > 1 { stack.append((index, end)) }
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func perpendicularDistance(_ p: TrackPoint, _ a: TrackPoint, _ b: TrackPoint) -> Double {
        let kx = 111_320 * cos(a.latitude * .pi / 180), ky = 110_540.0
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * kx, by = (b.latitude - a.latitude) * ky
        let px = (p.longitude - a.longitude) * kx, py = (p.latitude - a.latitude) * ky
        let len2 = bx * bx + by * by
        guard len2 > 0 else { return hypot(px - ax, py - ay) }
        let t = max(0, min(1, (px * bx + py * by) / len2))
        return hypot(px - t * bx, py - t * by)
    }
}
