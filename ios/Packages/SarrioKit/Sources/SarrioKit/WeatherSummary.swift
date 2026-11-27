import Foundation

/// Resumen del tiempo durante una salida a partir de horas de un servicio meteorológico: qué parte
/// del tiempo hizo sol, estuvo nublado, hubo niebla, lluvia o nieve, la temperatura y el viento.
public struct WeatherSummary: Sendable, Equatable {
    public enum Sky: String, Sendable, CaseIterable, Equatable {
        case sunny, cloudy, fog, rain, snow
    }

    /// Una hora de datos (empieza en `start` y dura 60 min).
    public struct Hour: Sendable, Equatable {
        public var start: Date
        public var sky: Sky
        /// °C
        public var temperature: Double
        /// km/h
        public var wind: Double
        public var gust: Double?

        public init(start: Date, sky: Sky, temperature: Double, wind: Double, gust: Double? = nil) {
            self.start = start; self.sky = sky; self.temperature = temperature; self.wind = wind; self.gust = gust
        }
    }

    /// Fracción (0…1) de la salida con cada estado, ponderada por los minutos de cada hora.
    public var shares: [Sky: Double]
    public var minTemperature: Double
    public var maxTemperature: Double
    public var maxWind: Double
    public var maxGust: Double?
    /// La hora más cercana a la cumbre, si se pide.
    public var atSummit: Hour?

    /// `nil` si ninguna hora cae dentro de la salida.
    public init?(hours: [Hour], from start: Date, to end: Date, summitAt: Date? = nil) {
        let end = max(end, start.addingTimeInterval(60))
        var weights: [(Hour, Double)] = []
        for h in hours {
            let hStart = h.start, hEnd = h.start.addingTimeInterval(3600)
            let overlap = min(hEnd, end).timeIntervalSince(max(hStart, start))
            if overlap > 0 { weights.append((h, overlap)) }
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var shares: [Sky: Double] = [:]
        for (h, w) in weights { shares[h.sky, default: 0] += w / total }
        self.shares = shares
        minTemperature = weights.map { $0.0.temperature }.min() ?? 0
        maxTemperature = weights.map { $0.0.temperature }.max() ?? 0
        maxWind = weights.map { $0.0.wind }.max() ?? 0
        maxGust = weights.compactMap { $0.0.gust }.max()
        if let summitAt {
            atSummit = hours.min { abs($0.start.addingTimeInterval(1800).timeIntervalSince(summitAt)) < abs($1.start.addingTimeInterval(1800).timeIntervalSince(summitAt)) }
        } else {
            atSummit = nil
        }
    }

    /// Los estados que pasan del 5 %, de más a menos.
    public var significant: [(sky: Sky, share: Double)] {
        shares.filter { $0.value >= 0.05 }.map { (sky: $0.key, share: $0.value) }.sorted { $0.share > $1.share }
    }
}
