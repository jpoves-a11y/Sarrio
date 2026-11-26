import Foundation

/// Deporte de una actividad, con el mismo valor que guarda la API (`sport_type`).
public enum SportType: String, Sendable, Codable, CaseIterable {
    case hiking
    case mountaineering
    case trailRunning = "trail_running"
    case running
    case walking
    case cycling
    case backcountrySkiing = "backcountry_skiing"
    case skiing
    case snowshoeing
    case climbing
    case other

    /// Nombre para la interfaz.
    public var title: String {
        switch self {
        case .hiking: "Senderismo"
        case .mountaineering: "Montañismo"
        case .trailRunning: "Trail running"
        case .running: "Carrera"
        case .walking: "Caminata"
        case .cycling: "Ciclismo"
        case .backcountrySkiing: "Esquí de montaña"
        case .skiing: "Esquí"
        case .snowshoeing: "Raquetas"
        case .climbing: "Escalada"
        case .other: "Actividad"
        }
    }

    /// Actividades de montaña: las que se listan en el perfil aunque no tengan cumbres.
    public var isMountain: Bool {
        switch self {
        case .hiking, .trailRunning, .mountaineering, .snowshoeing, .backcountrySkiing, .climbing: true
        default: false
        }
    }

    /// Apple Health no distingue el trail de la carrera: una carrera con más de 25 m de desnivel
    /// positivo por km se considera trail running.
    public static func refined(_ sport: SportType, distance: Double?, elevationGain: Double?) -> SportType {
        guard sport == .running, let distance, distance > 1000, let gain = elevationGain else { return sport }
        return gain / (distance / 1000) > 25 ? .trailRunning : .running
    }

    /// Deporte FIT (`sport`, mensaje `session`), según el perfil del FIT SDK.
    public init(fitSport: UInt8, subSport: UInt8? = nil) {
        switch fitSport {
        case 1: self = subSport == 3 ? .trailRunning : .running
        case 2, 21: self = .cycling
        case 11: self = .walking
        case 12: self = .backcountrySkiing
        case 13, 14: self = subSport == 37 ? .backcountrySkiing : .skiing
        case 16: self = .mountaineering
        case 17: self = .hiking
        case 31: self = .climbing
        case 35: self = .snowshoeing
        default: self = .other
        }
    }

    /// Atributo `Sport` de TCX (`Running`, `Biking`, `Other`).
    public init(tcxSport: String) {
        switch tcxSport.lowercased() {
        case "running": self = .running
        case "biking": self = .cycling
        default: self = .other
        }
    }
}
