import Foundation

enum Visibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case `private`, friends, `public`
    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: "Solo yo"
        case .friends: "Amigos"
        case .public: "Todos"
        }
    }

    var icon: String {
        switch self {
        case .private: "lock.fill"
        case .friends: "person.2.fill"
        case .public: "globe"
        }
    }
}

/// El usuario autenticado (`GET /v1/me`).
struct Me: Codable, Equatable, Sendable {
    var id: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarKey: String?
    var city: String?
    /// Ya eligió su usuario: no se puede cambiar.
    var usernameLocked: Bool?
    var defaultVisibility: Visibility
    var createdAt: Date
}

/// Perfil público de otro usuario (`GET /v1/users/:username`).
struct PublicUser: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarKey: String?
    var city: String?
}

struct AuthResponse: Decodable, Sendable {
    var token: String
    var isNew: Bool
    var user: Me
}

struct ProfileUpdate: Encodable, Sendable {
    var displayName: String?
    var bio: String?
    var city: String?
    var defaultVisibility: Visibility?
}
