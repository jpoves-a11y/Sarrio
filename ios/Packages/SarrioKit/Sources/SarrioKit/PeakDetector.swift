import Foundation

/// Una cumbre detectada en un track.
public struct DetectedSummit: Sendable, Hashable {
    public var peak: Peak
    /// Punto del track más cercano a la cima.
    public var closestPoint: TrackPoint
    public var distance: Double
}

/// Decide qué picos se han coronado en un track.
///
/// Reglas (ajustables):
/// - Algún punto a ≤ `maxHorizontalDistance` m de la cima **y** con altitud a ≤ `maxElevationDelta` m de la `ele` de OSM.
/// - Si el track o el pico no tienen altitud, se exige estar a ≤ `strictHorizontalDistance` m.
public struct PeakDetector: Sendable {
    public var maxHorizontalDistance: Double = 40
    public var strictHorizontalDistance: Double = 25
    public var maxElevationDelta: Double = 50

    public init() {}

    public func detect(track: [TrackPoint], candidates: [Peak]) -> [DetectedSummit] {
        guard let box = BoundingBox(points: track)?.expanded(byMeters: maxHorizontalDistance) else { return [] }
        let nearby = candidates.filter { box.contains(latitude: $0.lat, longitude: $0.lon) }
        guard !nearby.isEmpty else { return [] }

        var summits: [DetectedSummit] = []
        for peak in nearby {
            var best: (point: TrackPoint, distance: Double)?
            for point in track {
                let d = Geo.distance(point.latitude, point.longitude, peak.lat, peak.lon)
                guard d <= maxHorizontalDistance else { continue }
                if passesElevation(point: point, peak: peak, distance: d), d < (best?.distance ?? .infinity) {
                    best = (point, d)
                }
            }
            if let best {
                summits.append(DetectedSummit(peak: peak, closestPoint: best.point, distance: best.distance))
            }
        }
        // Orden cronológico de la ascensión (si hay tiempos) o por distancia.
        return summits.sorted {
            if let a = $0.closestPoint.time, let b = $1.closestPoint.time { return a < b }
            return $0.distance < $1.distance
        }
    }

    private func passesElevation(point: TrackPoint, peak: Peak, distance: Double) -> Bool {
        guard let trackEle = point.elevation, let peakEle = peak.ele else {
            return distance <= strictHorizontalDistance
        }
        return abs(trackEle - peakEle) <= maxElevationDelta
    }
}
