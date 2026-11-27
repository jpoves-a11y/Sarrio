import Foundation

/// Análisis de una salida a partir de su ruta (altitud y, si los hay, tiempos): pendientes, ritmo de
/// subida y parciales por km. Lógica pura para la pestaña «Análisis» del detalle de actividad.
public struct ActivityAnalysis: Sendable {
    /// Un tramo de unos 100 m con su pendiente.
    public struct Slope: Sendable, Equatable {
        /// Distancia (m) al inicio del tramo.
        public var start: Double
        public var length: Double
        /// Pendiente en % (positiva subiendo).
        public var grade: Double
    }

    /// Reparto de la distancia por pendiente (en metros por clase).
    public struct SlopeBuckets: Sendable, Equatable {
        public var flat = 0.0, easy = 0.0, moderate = 0.0, hard = 0.0, veryHard = 0.0
        public var total: Double { flat + easy + moderate + hard + veryHard }
    }

    /// Velocidad vertical (m/h) en una ventana de tiempo.
    public struct RatePoint: Sendable, Equatable {
        /// Segundos desde el inicio.
        public var time: Double
        public var rate: Double
    }

    /// Un kilómetro: cuánto tardó y cuánto subió y bajó.
    public struct Split: Sendable, Equatable {
        public var km: Int
        public var seconds: Double?
        public var gain: Double
        public var loss: Double
    }

    public var slopes: [Slope]
    public var buckets: SlopeBuckets
    /// Los ~500 m seguidos con más pendiente media.
    public var hardest: Slope?
    /// Velocidad vertical en ventanas de 5 min (vacía sin tiempos).
    public var rates: [RatePoint]
    /// El mejor tramo de 15 min subiendo (m/h).
    public var bestClimb15: Double?
    public var movingSeconds: Double?
    public var stoppedSeconds: Double?
    public var splits: [Split]

    public var hasTimes: Bool { !rates.isEmpty }

    public init(points: [TrackPoint]) {
        let pts = points.filter { $0.elevation != nil }
        // Distancia acumulada
        var cum: [Double] = [0]
        for i in 1..<max(1, pts.count) { cum.append(cum[i - 1] + Geo.distance(pts[i - 1], pts[i])) }

        // Pendientes en tramos de ~100 m
        var slopes: [Slope] = []
        var startIdx = 0
        for i in 1..<max(1, pts.count) where cum[i] - cum[startIdx] >= 100 || i == pts.count - 1 {
            let len = cum[i] - cum[startIdx]
            guard len >= 20 else { continue }
            let rise = (pts[i].elevation ?? 0) - (pts[startIdx].elevation ?? 0)
            slopes.append(Slope(start: cum[startIdx], length: len, grade: rise / len * 100))
            startIdx = i
        }
        self.slopes = slopes

        var buckets = SlopeBuckets()
        for s in slopes {
            switch abs(s.grade) {
            case ..<5: buckets.flat += s.length
            case ..<10: buckets.easy += s.length
            case ..<20: buckets.moderate += s.length
            case ..<30: buckets.hard += s.length
            default: buckets.veryHard += s.length
            }
        }
        self.buckets = buckets

        // Tramo más duro: ventana de ~500 m con más pendiente media (subiendo)
        var hardest: Slope?
        for i in slopes.indices {
            var len = 0.0, rise = 0.0, j = i
            while j < slopes.count, len < 500 {
                len += slopes[j].length
                rise += slopes[j].grade / 100 * slopes[j].length
                j += 1
            }
            guard len >= 300 else { continue }
            let grade = rise / len * 100
            if grade > (hardest?.grade ?? 0) { hardest = Slope(start: slopes[i].start, length: len, grade: grade) }
        }
        self.hardest = hardest

        // Tiempos
        let timed = pts.filter { $0.time != nil }
        guard timed.count >= 2, let t0 = timed.first?.time else {
            rates = []; bestClimb15 = nil; movingSeconds = nil; stoppedSeconds = nil
            splits = Self.splits(pts, cum: cum, times: nil)
            return
        }
        let secs = timed.map { $0.time!.timeIntervalSince(t0) }

        // Velocidad vertical en ventanas de 5 min
        var rates: [RatePoint] = []
        var w = 0
        for i in 1..<timed.count where secs[i] - secs[w] >= 300 || i == timed.count - 1 {
            let dt = secs[i] - secs[w]
            guard dt >= 60 else { continue }
            let de = (timed[i].elevation ?? 0) - (timed[w].elevation ?? 0)
            rates.append(RatePoint(time: (secs[i] + secs[w]) / 2, rate: max(-3000, min(3000, de / dt * 3600))))
            w = i
        }
        self.rates = rates

        // Mejor tramo de 15 min subiendo
        var best: Double?
        var j = 0
        for i in timed.indices {
            while j < timed.count, secs[j] - secs[i] < 900 { j += 1 }
            guard j < timed.count else { break }
            let de = (timed[j].elevation ?? 0) - (timed[i].elevation ?? 0)
            let rate = de / (secs[j] - secs[i]) * 3600
            if rate > (best ?? 0) { best = min(3000, rate) }
        }
        self.bestClimb15 = best

        // En movimiento: tramos a más de 0,3 m/s (parado si va más lento o hay huecos largos)
        var moving = 0.0, stopped = 0.0
        for i in 1..<timed.count {
            let dt = secs[i] - secs[i - 1]
            guard dt > 0 else { continue }
            let v = Geo.distance(timed[i - 1], timed[i]) / dt
            if v >= 0.3 && dt < 600 { moving += dt } else { stopped += dt }
        }
        movingSeconds = moving
        stoppedSeconds = stopped

        var timedCum: [Double] = [0]
        for i in 1..<timed.count { timedCum.append(timedCum[i - 1] + Geo.distance(timed[i - 1], timed[i])) }
        splits = Self.splits(timed, cum: timedCum, times: secs)
    }

    /// Parciales por km (el último, si es parcial, solo si pasa de 300 m).
    private static func splits(_ pts: [TrackPoint], cum: [Double], times: [Double]?) -> [Split] {
        guard pts.count >= 2, let total = cum.last, total >= 300 else { return [] }
        var out: [Split] = []
        var km = 1, startIdx = 0, gain = 0.0, loss = 0.0
        for i in 1..<pts.count {
            let de = (pts[i].elevation ?? 0) - (pts[i - 1].elevation ?? 0)
            if de > 0 { gain += de } else { loss -= de }
            let isLast = i == pts.count - 1
            if cum[i] >= Double(km) * 1000 || isLast {
                let length = cum[i] - cum[startIdx]
                if !isLast || length >= 300 || out.isEmpty {
                    let seconds = times.map { $0[i] - $0[startIdx] }
                    out.append(Split(km: km, seconds: seconds, gain: gain.rounded(), loss: loss.rounded()))
                }
                km += 1; startIdx = i; gain = 0; loss = 0
            }
        }
        return out
    }
}
