import Foundation
import SwiftUI

// MARK: - Lectura tolerante
// El servidor puede añadir niveles, métricas o retos nuevos antes de que la app se actualice:
// lo desconocido toma un valor por defecto y lo que no se puede leer se salta, sin romper la pantalla.

/// Enum que, ante un valor desconocido, usa `fallback` en lugar de fallar.
protocol TolerantEnum: RawRepresentable, Decodable where RawValue == String {
    static var fallback: Self { get }
}

extension TolerantEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

/// Lista que se salta los elementos que no puede leer.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                out.append(element)
            } else if (try? container.decode(Skip.self)) == nil {
                break // no se puede avanzar: mejor parar que dar vueltas
            }
        }
        elements = out
    }

    private struct Skip: Decodable {}
}

/// Nivel del emblema (el color del medallón).
enum BadgeTier: String, Codable, Sendable, TolerantEnum {
    static let fallback = BadgeTier.gold

    case bronze, silver, gold, special, legend

    var title: String {
        switch self {
        case .bronze: "Bronce"
        case .silver: "Plata"
        case .gold: "Oro"
        case .special: "Especial"
        case .legend: "Leyenda"
        }
    }
}

/// Colores de las Leyendas: obsidiana y oro (como su medallón).
enum LegendColors {
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let gold = Color(red: 0.89, green: 0.74, blue: 0.38)
}

struct BadgeProgress: Codable, Hashable, Sendable {
    var value: Double
    var target: Double
    var fraction: Double { target > 0 ? min(1, value / target) : 0 }
}

/// Un emblema del catálogo, con su estado para mí.
struct Badge: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var description: String
    var tier: BadgeTier
    var category: String
    /// Nombre del asset en `Badges.xcassets`.
    var icon: String
    var earnedAt: Date?
    var activityId: String?
    var ascentId: String?
    var progress: BadgeProgress?

    var isEarned: Bool { earnedAt != nil }

    /// "6.200 / 8.849 m", "12 / 25"… según el emblema.
    var progressText: String? {
        guard let progress else { return nil }
        let unit: (Double) -> String
        switch id {
        case "km-100", "km-1000", "ultra": unit = { "\(Int(($0 / 1000).rounded()).formatted())" }
        default: unit = { Int($0.rounded()).formatted() }
        }
        let suffix: String
        switch id {
        case "km-100", "km-1000", "ultra": suffix = " km"
        case "alt-2000", "alt-3000", "alt-4000", "gain-10k", "everest", "everest-10", "long-day", "everesting", "hundred-k": suffix = " m"
        case "king-pyrenees", "lord-alps", "iberian-slam": suffix = " cimas"
        case "streak-4", "streak-12": suffix = " sem."
        default: suffix = ""
        }
        return "\(unit(progress.value)) / \(unit(progress.target))\(suffix)"
    }
}

struct BadgeCatalog: Decodable, Sendable {
    var badges: [Badge]
    var earned: Int
    var total: Int

    private enum CodingKeys: String, CodingKey { case badges, earned, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        badges = try c.decode(LossyArray<Badge>.self, forKey: .badges).elements
        earned = try c.decode(Int.self, forKey: .earned)
        total = try c.decode(Int.self, forKey: .total)
    }
}

/// Emblema recién conseguido (viene en la respuesta de una subida).
struct NewBadge: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var description: String
    var tier: BadgeTier
    var category: String
    var icon: String
}

// MARK: - Retos

enum ChallengeKind: String, Codable, Sendable, TolerantEnum {
    case metric, peaks
    static let fallback = ChallengeKind.metric
}

enum ChallengeMetric: String, Codable, Sendable, CaseIterable, Identifiable, TolerantEnum {
    case elevationGain = "elevation_gain"
    case distance
    case summits
    case uniquePeaks = "unique_peaks"
    case activities
    case activeWeeks = "active_weeks"
    case highSummits = "high_summits"
    case sunriseSummits = "sunrise_summits"
    case maxActivityGain = "max_activity_gain"
    /// Métrica que esta versión de la app aún no conoce.
    case unknown

    static let fallback = ChallengeMetric.unknown

    var id: String { rawValue }

    /// Las que se pueden elegir al crear un reto propio.
    static let creatable: [ChallengeMetric] = [.elevationGain, .distance, .summits, .uniquePeaks, .activities, .activeWeeks]

    var title: String {
        switch self {
        case .elevationGain: "Desnivel positivo"
        case .distance: "Distancia"
        case .summits: "Cimas"
        case .uniquePeaks: "Cimas distintas"
        case .activities: "Salidas"
        case .activeWeeks: "Semanas con salida"
        case .highSummits: "Cimas altas"
        case .sunriseSummits: "Cimas al amanecer"
        case .maxActivityGain: "Desnivel en una actividad"
        case .unknown: "Progreso"
        }
    }

    var unit: String {
        switch self {
        case .elevationGain, .maxActivityGain: "m D+"
        case .distance: "km"
        case .summits, .uniquePeaks, .highSummits, .sunriseSummits: "cimas"
        case .activities: "salidas"
        case .activeWeeks: "semanas"
        case .unknown: ""
        }
    }

    /// Valor que se enseña (la distancia viaja en metros).
    func display(_ value: Double) -> String {
        switch self {
        case .distance: Int((value / 1000).rounded(.down)).formatted()
        default: Int(value.rounded()).formatted()
        }
    }
}

struct ChallengeProgress: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable, TolerantEnum {
        case active, upcoming, ended
        static let fallback = Status.active
    }
    var value: Double
    var target: Double
    var fraction: Double
    var done: Bool
    var status: Status
    var periodStart: Date?
    var periodEnd: Date?
}

struct ChallengeCreator: Codable, Hashable, Sendable {
    var id: String
    var username: String
    var displayName: String
}

struct Challenge: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var slug: String?
    var official: Bool
    var creatorId: String?
    var title: String
    var description: String?
    var visibility: Visibility
    var kind: ChallengeKind
    var metric: ChallengeMetric?
    var target: Double?
    var sport: String?
    var minEle: Double?
    var recurrence: String
    var window: String?
    /// Leyenda: el emblema que da completarlo (asset `badge-<id>`).
    var badgeId: String?
    var startsAt: Date?
    var endsAt: Date?
    var peakCount: Int?
    var participants: Int?
    var joined: Bool?
    var joinedAt: Date?
    var completedAt: Date?
    var progress: ChallengeProgress?
    var creator: ChallengeCreator?

    var isJoined: Bool { joined ?? false }
    var isLegend: Bool { badgeId != nil }

    /// "6.200 / 8.849 m D+" o "4 / 15 cimas".
    var valueText: (value: String, target: String, unit: String) {
        let p = progress ?? ChallengeProgress(value: 0, target: target ?? 0, fraction: 0, done: false, status: .active)
        if kind == .peaks { return (Int(p.value).formatted(), Int(p.target).formatted(), "cimas") }
        let m = metric ?? .summits
        return (m.display(p.value), m.display(p.target), m.unit)
    }

    /// "Quedan 35 días", "Empieza el 21 jun", "Terminado"…
    var periodText: String? {
        guard let p = progress else { return nil }
        let now = Date()
        switch p.status {
        case .upcoming:
            return p.periodStart.map { "Empieza el \($0.formatted(.dateTime.day().month(.abbreviated)))" }
        case .ended:
            return "Terminado"
        case .active:
            guard let end = p.periodEnd else { return nil }
            let days = Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0
            if days <= 0 { return "Último día" }
            if days == 1 { return "Queda 1 día" }
            return "Quedan \(days) días"
        }
    }

    /// "Cada mes", "Cada año", "Del 21 jun al 22 sept"…
    var periodKind: String {
        switch recurrence {
        case "monthly": return "Cada mes"
        case "yearly":
            if let p = progress, window != nil, let s = p.periodStart, let e = p.periodEnd {
                let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
                return "Del \(s.formatted(f)) al \(e.addingTimeInterval(-1).formatted(f))"
            }
            return "Cada año"
        default:
            if let s = startsAt, let e = endsAt {
                let f = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
                return "Del \(s.formatted(f)) al \(e.formatted(f))"
            }
            return kind == .peaks ? "Sin fecha límite" : "Sin fecha"
        }
    }
}

struct ChallengeList: Decodable, Sendable {
    var challenges: [Challenge]

    private enum CodingKeys: String, CodingKey { case challenges }

    init(from decoder: Decoder) throws {
        challenges = try decoder.container(keyedBy: CodingKeys.self).decode(LossyArray<Challenge>.self, forKey: .challenges).elements
    }
}

struct ChallengePeak: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var name: String
    var nameEs: String?
    var ele: Double?
    var lat: Double
    var lon: Double
    var range: String?
    var done: Bool

    var ref: PeakRef { PeakRef(id: id, name: name, nameEs: nameEs, ele: ele, lat: lat, lon: lon, range: range) }
}

struct ChallengeDetail: Decodable, Sendable {
    var challenge: Challenge
    var peaks: [ChallengePeak]
}

struct NewChallenge: Encodable, Sendable {
    var kind: ChallengeKind
    var title: String
    var description: String?
    var visibility: Visibility
    var metric: ChallengeMetric?
    var target: Double?
    var startsAt: Int64?
    var endsAt: Int64?
    var peakIds: [Int64]?
}
