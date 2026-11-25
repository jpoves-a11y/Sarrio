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
    var defaultVisibility: Visibility
    var createdAt: Date
}

/// Perfil público de otro usuario (`GET /v1/users/:username`).
struct PublicUser: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarKey: String?
}

struct AuthResponse: Decodable, Sendable {
    var token: String
    var isNew: Bool
    var user: Me
}

struct ProfileUpdate: Encodable, Sendable {
    var username: String?
    var displayName: String?
    var bio: String?
    var defaultVisibility: Visibility?
}
