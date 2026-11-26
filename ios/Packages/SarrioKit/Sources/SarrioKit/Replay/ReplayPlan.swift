import Foundation

/// Coordenada simple (SarrioKit no depende de CoreLocation, para poder probarse en Linux).
public struct GeoPoint: Sendable, Hashable, Codable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// La ruta preparada para el replay: remuestreada a intervalos iguales y suavizada (fuera los
/// zigzags del GPS), con la distancia recorrida en cada punto, la altitud, dónde está el montañero
/// tras cualquier distancia y hacia dónde va. Lleva además una copia mucho más suave para la
/// cámara: atraviesa las curvas con fluidez sin despegarse del montañero.
///
/// Basado en el replay de KM2 (`RouteReplayPlan`), con las cumbres de la actividad a lo largo de la ruta.
public struct ReplayPlan: Sendable {
    public let points: [GeoPoint]
    /// Altitud de cada punto (nil si la ruta no la trae).
    public let elevations: [Double?]
    /// Metros desde el inicio hasta cada punto.
    public let cumulative: [Double]
    /// La ruta promediada en ±70-380 m, punto a punto con `points`: el camino de la cámara.
    public let cameraPoints: [GeoPoint]
    public let length: Double
    public let center: GeoPoint
    /// Lado mayor de la caja de la ruta, en metros.
    public let extent: Double
    /// Distancia a lo largo de la ruta del punto más cercano a cada cumbre, en orden.
    public let summitDistances: [Double]

    /// Como mucho tantos puntos (coste del trabajo por fotograma).
    static let maxPoints = 900

    /// `summits`: posiciones de las cumbres de la actividad (se sitúan sobre la ruta).
    public init?(track: [TrackPoint], summits: [GeoPoint] = []) {
        let usable = track.filter { abs($0.latitude) <= 90 && abs($0.longitude) <= 180 && !($0.latitude == 0 && $0.longitude == 0) }
        let valid = Self.withoutKnots(usable)
        guard valid.count >= 2 else { return nil }

        var rawCumulative: [Double] = [0]
        for i in 1..<valid.count {
            rawCumulative.append(rawCumulative[i - 1] + Geo.distance(valid[i - 1], valid[i]))
        }
        guard let rawLength = rawCumulative.last, rawLength > 1 else { return nil }

        // 1. Remuestreo cada `spacing` metros
        let spacing = max(4, rawLength / Double(Self.maxPoints - 1))
        var resampled: [GeoPoint] = []
        var resampledEle: [Double?] = []
        var segment = 0
        var target = 0.0
        while target < rawLength {
            while segment < valid.count - 2 && rawCumulative[segment + 1] < target { segment += 1 }
            let a = valid[segment], b = valid[segment + 1]
            let span = rawCumulative[segment + 1] - rawCumulative[segment]
            let f = span > 0 ? (target - rawCumulative[segment]) / span : 0
            resampled.append(GeoPoint(lat: a.latitude + (b.latitude - a.latitude) * f, lon: a.longitude + (b.longitude - a.longitude) * f))
            if let ea = a.elevation, let eb = b.elevation { resampledEle.append(ea + (eb - ea) * f) } else { resampledEle.append(a.elevation ?? b.elevation) }
            target += spacing
        }
        resampled.append(GeoPoint(lat: valid[valid.count - 1].latitude, lon: valid[valid.count - 1].longitude))
        resampledEle.append(valid[valid.count - 1].elevation)

        // 2. Media móvil de ~40 m (los extremos se quedan donde están); la altitud, de ~60 m
        let smoothed = Self.movingAverage(resampled, half: max(1, Int((20 / spacing).rounded())))
        let smoothedEle = Self.movingAverage(resampledEle, half: max(1, Int((30 / spacing).rounded())))

        var distances: [Double] = [0]
        for i in 1..<smoothed.count {
            distances.append(distances[i - 1] + Geo.distance(smoothed[i - 1].lat, smoothed[i - 1].lon, smoothed[i].lat, smoothed[i].lon))
        }
        guard let total = distances.last, total > 1 else { return nil }

        let lats = smoothed.map(\.lat), lons = smoothed.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let midLat = (minLat + maxLat) / 2
        let height = (maxLat - minLat) * 111_320
        let width = (maxLon - minLon) * 111_320 * cos(midLat * .pi / 180)

        // 3. El camino de la cámara: media móvil de ±2,5 % de la ruta (70-380 m) con sumas prefijas;
        //    la ventana se estrecha en los extremos para que empiece y acabe sobre la ruta
        let cameraHalf = max(1, Int((min(380, max(70, total * 0.025)) / spacing).rounded()))
        var prefixLat: [Double] = [0], prefixLon: [Double] = [0]
        for p in smoothed {
            prefixLat.append(prefixLat[prefixLat.count - 1] + p.lat)
            prefixLon.append(prefixLon[prefixLon.count - 1] + p.lon)
        }
        var camera: [GeoPoint] = []
        camera.reserveCapacity(smoothed.count)
        for i in 0..<smoothed.count {
            let half = min(cameraHalf, i, smoothed.count - 1 - i)
            let from = i - half, to = i + half
            let n = Double(to - from + 1)
            camera.append(GeoPoint(lat: (prefixLat[to + 1] - prefixLat[from]) / n, lon: (prefixLon[to + 1] - prefixLon[from]) / n))
        }

        points = smoothed
        elevations = smoothedEle
        cumulative = distances
        cameraPoints = camera
        length = total
        center = GeoPoint(lat: midLat, lon: (minLon + maxLon) / 2)
        extent = max(height, width, 200)
        summitDistances = summits.map { s in
            var best = (index: 0, d: Double.infinity)
            for (i, p) in smoothed.enumerated() {
                let d = Geo.distance(p.lat, p.lon, s.lat, s.lon)
                if d < best.d { best = (i, d) }
            }
            return distances[best.index]
        }.sorted()
    }

    private static func movingAverage(_ values: [GeoPoint], half: Int) -> [GeoPoint] {
        guard values.count > 2 * half + 1 else { return values }
        var out = values
        for i in 1..<(values.count - 1) {
            let from = max(0, i - half), to = min(values.count - 1, i + half)
            var lat = 0.0, lon = 0.0
            for k in from...to { lat += values[k].lat; lon += values[k].lon }
            let n = Double(to - from + 1)
            out[i] = GeoPoint(lat: lat / n, lon: lon / n)
        }
        return out
    }

    private static func movingAverage(_ values: [Double?], half: Int) -> [Double?] {
        guard values.count > 2 * half + 1 else { return values }
        var out = values
        for i in values.indices {
            let window = values[max(0, i - half)...min(values.count - 1, i + half)].compactMap { $0 }
            out[i] = window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
        }
        return out
    }

    /// La ruta sin los «nudos» del GPS: donde el montañero paró (una fuente, una foto en la cima) o
    /// la señal fue mala, el track da vueltas pequeñas de 10-30 m que, reproducidas a cientos de
    /// metros por segundo, hacían temblar al montañero. Se quitan los puntos a menos de 3 m del
    /// último guardado, y se corta el tramo que vuelve a menos de 12 m de un punto de los últimos
    /// 100 m tras recorrer más de 25 m y el triple de su dispersión, sin alejarse más de 20 m.
    /// Las curvas reales (una lazada, un zigzag de senda) recorren mucho menos del triple de su
    /// dispersión, así que se quedan. Igual que en KM2.
    static func withoutKnots(_ track: [TrackPoint]) -> [TrackPoint] {
        guard track.count > 2 else { return track }
        let kx = cos(track[0].latitude * .pi / 180) * 111_320
        let ky = 110_574.0
        func flat(_ p: TrackPoint) -> (x: Double, y: Double) { (p.longitude * kx, p.latitude * ky) }
        func gap(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double { hypot(a.x - b.x, a.y - b.y) }

        var kept = [track[0]]
        var keptFlat = [flat(track[0])]
        var along = [0.0]
        for p in track.dropFirst() {
            let point = flat(p)
            guard let last = keptFlat.last, gap(point, last) >= 3 else { continue }
            let here = along[along.count - 1] + gap(last, point)
            var cut: Int?
            var j = keptFlat.count - 2
            while j >= 0 && here - along[j] <= 100 {
                let back = gap(keptFlat[j], point)
                let path = here - along[j]
                if back < 12 && path > 25 {
                    var spread = back
                    for k in (j + 1)..<keptFlat.count { spread = max(spread, gap(keptFlat[k], keptFlat[j])) }
                    if spread <= 20 && path > 3 * spread { cut = j }
                }
                j -= 1
            }
            if let cut {
                kept.removeSubrange((cut + 1)...)
                keptFlat.removeSubrange((cut + 1)...)
                along.removeSubrange((cut + 1)...)
            }
            guard let end = keptFlat.last, gap(point, end) >= 3 else { continue }
            along.append(along[along.count - 1] + gap(end, point))
            kept.append(p)
            keptFlat.append(point)
        }
        if let finish = track.last, kept.count >= 2 { kept[kept.count - 1] = finish }
        return kept
    }

    // MARK: - Consultas

    private func segment(at distance: Double) -> Int {
        var low = 0, high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= distance { low = mid } else { high = mid }
        }
        return low
    }

    private func fraction(at distance: Double) -> (index: Int, next: Int, f: Double) {
        let d = min(max(0, distance), length)
        let i = segment(at: d)
        let j = min(i + 1, cumulative.count - 1)
        let span = cumulative[j] - cumulative[i]
        return (i, j, span > 0 ? (d - cumulative[i]) / span : 0)
    }

    private func interpolate(_ along: [GeoPoint], at distance: Double) -> GeoPoint {
        let (i, j, f) = fraction(at: distance)
        return GeoPoint(lat: along[i].lat + (along[j].lat - along[i].lat) * f, lon: along[i].lon + (along[j].lon - along[i].lon) * f)
    }

    /// Dónde está el montañero tras `distance` metros.
    public func coordinate(at distance: Double) -> GeoPoint { interpolate(points, at: distance) }

    /// Altitud tras `distance` metros (nil sin datos).
    public func elevation(at distance: Double) -> Double? {
        let (i, j, f) = fraction(at: distance)
        guard let a = elevations[i] else { return elevations[j] }
        guard let b = elevations[j] else { return a }
        return a + (b - a) * f
    }

    /// Desnivel positivo acumulado hasta `distance` (histéresis de 3 m, como `ParsedTrack`).
    public func elevationGain(upTo distance: Double) -> Double {
        let last = segment(at: min(max(0, distance), length))
        var gain = 0.0
        var reference: Double?
        for e in elevations[0...last].compactMap({ $0 }) {
            guard let ref = reference else { reference = e; continue }
            if e - ref >= 3 { gain += e - ref; reference = e } else if ref - e >= 3 { reference = e }
        }
        return gain
    }

    /// Dónde mira la cámara cuando el montañero va por `distance` (sobre la ruta suavizada).
    public func cameraCoordinate(at distance: Double) -> GeoPoint { interpolate(cameraPoints, at: distance) }

    /// Rumbo de la cámara: a lo largo de la ruta suavizada, mirando bastante por delante para
    /// anticipar las curvas.
    public func cameraBearing(at distance: Double) -> Double {
        Self.bearing(from: cameraCoordinate(at: distance - 100), to: cameraCoordinate(at: distance + 350))
    }

    public static func bearing(from: GeoPoint, to: GeoPoint) -> Double {
        let lat1 = from.lat * .pi / 180, lat2 = to.lat * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
