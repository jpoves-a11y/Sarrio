import Foundation
import SarrioKit

/// Pico tal como viene dentro de una ascensión.
struct PeakRef: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var name: String
    var nameEs: String?
    var ele: Double?
    var lat: Double
    var lon: Double
    var range: String?

    var displayName: String { nameEs ?? name }

    init(id: Int64, name: String, nameEs: String?, ele: Double?, lat: Double, lon: Double, range: String? = nil) {
        self.id = id; self.name = name; self.nameEs = nameEs; self.ele = ele; self.lat = lat; self.lon = lon; self.range = range
    }

    init(_ peak: Peak) {
        self.init(id: peak.id, name: peak.name, nameEs: peak.nameEs, ele: peak.ele, lat: peak.lat, lon: peak.lon, range: peak.range)
    }
}

struct Ascent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var userId: String
    var activityId: String?
    var summitedAt: Date
    var note: String?
    var visibility: Visibility
    var peak: PeakRef
}

struct BoundingBoxDTO: Codable, Hashable, Sendable {
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double
}

struct Activity: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var userId: String
    var source: String
    var sportType: String
    var title: String?
    var startAt: Date
    var durationS: Double?
    var distanceM: Double?
    var elevGainM: Double?
    var bbox: BoundingBoxDTO?
    var visibility: Visibility
    var createdAt: Date
    /// Solo en el listado (`GET /v1/activities`).
    var ascents: [Ascent]?

    var sport: SportType { SportType(rawValue: sportType) ?? .other }
    var displayTitle: String { title ?? sport.title }
}

/// `GET /v1/ascents`
struct Library: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        var ascents: Int
        var uniquePeaks: Int
        var highestPeak: PeakRef?
    }

    var ascents: [Ascent]
    var summary: Summary
}

/// `GET /v1/activities`
struct ActivityPage: Decodable, Sendable {
    var activities: [Activity]
    var nextBefore: Date?
}

/// `POST /v1/activities`, `PATCH /v1/activities/:id`
struct ActivityWithAscents: Decodable, Sendable {
    var activity: Activity
    var ascents: [Ascent]
    var created: Bool?
    var rejectedPeakIds: [Int64]?
    /// Emblemas que ha dado esta subida (para la celebración).
    var newBadges: [NewBadge]?
}

/// `GET /v1/activities/:id`: incluye la ruta en segmentos `[[lat, lon, ele?, t?]]`.
struct ActivityDetail: Decodable, Sendable {
    var activity: Activity
    var ascents: [Ascent]
    var track: [[[Double?]]]

    var segments: [[TrackPoint]] {
        track.map { segment in
            segment.compactMap { p in
                guard p.count >= 2, let lat = p[0], let lon = p[1] else { return nil }
                let time = p.count > 3 ? p[3].map { activity.startAt.addingTimeInterval($0) } : nil
                return TrackPoint(latitude: lat, longitude: lon, elevation: p.count > 2 ? p[2] : nil, time: time)
            }
        }
    }
}

struct ActivityUpdate: Encodable, Sendable {
    var title: String?
    var visibility: Visibility?
}

struct ManualAscent: Encodable, Sendable {
    var peakId: Int64
    var summitedAt: Int64
    var note: String?
}
