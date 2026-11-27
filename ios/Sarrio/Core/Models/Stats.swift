import Foundation

/// `GET /v1/me/stats?year=…`: estadísticas del perfil de un año o de siempre.
struct UserStats: Decodable, Sendable {
    struct Totals: Decodable, Sendable {
        var gain: Double
        var distance: Double
        var durationS: Double
        var activities: Int
        var summits: Int
        var uniquePeaks: Int
    }

    struct Cumulative: Decodable, Sendable {
        /// Puntos [día del año, metros acumulados].
        var current: [[Double]]
        var previous: [[Double]]
    }

    struct Month: Decodable, Sendable, Identifiable {
        var month: Int
        var gain: Double
        var distance: Double
        var activities: Int
        var id: Int { month }
    }

    struct Year: Decodable, Sendable, Identifiable {
        var year: Int
        var gain: Double
        var activities: Int
        var id: Int { year }
    }

    struct Day: Decodable, Sendable {
        var date: String
        var gain: Double
        var activityIds: [String]
    }

    struct Calendar: Decodable, Sendable {
        var start: String
        var days: [Day]
    }

    struct Streak: Decodable, Sendable {
        var current: Int
        var best: Int
    }

    struct Record: Decodable, Sendable {
        var value: Double
        var activityId: String
        var date: Date
        var title: String?
    }

    struct PeakRecord: Decodable, Sendable {
        var name: String
        var ele: Double?
        var date: Date
        var activityId: String?
        var peakId: Int64
    }

    struct Records: Decodable, Sendable {
        var gain: Record?
        var distance: Record?
        var duration: Record?
        var climbRate: Record?
        var highestPeak: PeakRecord?
    }

    struct ClimbRate: Decodable, Sendable, Identifiable {
        var date: Date
        var value: Double
        var activityId: String
        var id: String { activityId }
    }

    struct Peak: Decodable, Sendable, Identifiable {
        var id: Int64
        var name: String
        var ele: Double?
        var count: Int
    }

    var year: Int?
    var years: [Int]
    var totals: Totals
    var previousTotals: Totals?
    var cumulative: Cumulative?
    var monthly: [Month]
    var yearly: [Year]
    var calendar: Calendar
    var streak: Streak
    var records: Records
    var climbRates: [ClimbRate]
    var peaks: [Peak]
}

struct RouteLine: Decodable, Sendable, Identifiable {
    var activityId: String
    var points: [[Double]]
    var id: String { activityId }
}

struct Leaderboard: Decodable, Sendable {
    struct Row: Decodable, Sendable, Identifiable {
        var user: PublicUser
        var value: Double
        var isMe: Bool
        var id: String { user.id }
    }
    var metric: String
    var rows: [Row]
}
