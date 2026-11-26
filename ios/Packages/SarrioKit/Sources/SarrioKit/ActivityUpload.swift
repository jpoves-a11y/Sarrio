import Foundation

/// Cuerpo de `POST /v1/activities`: la actividad, su ruta simplificada y las cumbres detectadas.
public struct ActivityUpload: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case healthkit, file, manual, polar }

    public struct Ascent: Codable, Sendable, Equatable {
        public var peakId: Int64
        /// Milisegundos desde 1970.
        public var summitedAt: Int64
    }

    public var source: Source
    public var externalId: String
    public var sportType: String
    public var title: String?
    /// Milisegundos desde 1970.
    public var startAt: Int64
    public var durationS: Double?
    public var distanceM: Double?
    public var elevGainM: Double?
    /// `[[lat, lon, ele | null, t | null]]`, con `t` en segundos desde `startAt`.
    public var track: [[Double?]]
    public var ascents: [Ascent]

    /// Tolerancia de Douglas-Peucker: 3 m conserva la forma y reduce los puntos entre 5 y 10 veces.
    public static let simplifyTolerance = 3.0

    public init(
        track parsed: ParsedTrack,
        summits: [DetectedSummit],
        source: Source,
        externalId: String,
        sport: SportType? = nil,
        title: String? = nil,
        startDate: Date? = nil,
        duration: TimeInterval? = nil,
        distance: Double? = nil,
        elevationGain: Double? = nil
    ) {
        let start = startDate ?? parsed.startDate ?? Date()
        let summitIndices = Set(summits.compactMap { s in parsed.points.firstIndex(of: s.closestPoint) })
        let simplified = Geo.simplify(parsed.points, tolerance: Self.simplifyTolerance, keeping: summitIndices)

        self.source = source
        self.externalId = externalId
        let distanceM = (distance ?? parsed.distance).rounded()
        let elevGainM = (elevationGain ?? parsed.elevationGain()).rounded()
        // Una carrera con mucho desnivel es trail (Apple Health no los distingue)
        self.sportType = SportType.refined(sport ?? parsed.sport ?? .hiking, distance: distanceM, elevationGain: elevGainM).rawValue
        self.title = title ?? parsed.name
        self.startAt = Int64((start.timeIntervalSince1970 * 1000).rounded())
        self.durationS = (duration ?? parsed.duration)?.rounded()
        self.distanceM = distanceM
        self.elevGainM = elevGainM
        self.track = simplified.map { p in
            [
                (p.latitude * 1e6).rounded() / 1e6,
                (p.longitude * 1e6).rounded() / 1e6,
                p.elevation.map { ($0 * 10).rounded() / 10 },
                p.time.map { max(0, $0.timeIntervalSince(start)).rounded() },
            ]
        }
        self.ascents = summits.map { s in
            Ascent(
                peakId: s.peak.id,
                summitedAt: Int64(((s.closestPoint.time ?? start).timeIntervalSince1970 * 1000).rounded())
            )
        }
    }
}
