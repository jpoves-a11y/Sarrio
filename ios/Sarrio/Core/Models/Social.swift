import Foundation

/// Estado de amistad visto desde mí.
enum FriendStatus: String, Codable, Sendable, TolerantEnum {
    case notFriends = "none", friends, outgoing, incoming, blocked
    /// Mi propio perfil.
    case me = "self"
    static let fallback = FriendStatus.notFriends
}

/// Persona en listas de amigos, solicitudes y búsquedas.
struct Person: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var username: String
    var displayName: String
    var bio: String?
    var avatarKey: String?
    var friendStatus: FriendStatus?
    var since: Date?
}

struct FriendsList: Decodable, Sendable {
    var friends: [Person]
    var incoming: [Person]
    var outgoing: [Person]
}

/// Perfil de otra persona: sus cumbres visibles para mí y, si somos amigos, sus emblemas.
struct UserProfile: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        var ascents: Int
        var uniquePeaks: Int
        var highestPeak: PeakRef?
    }

    struct EarnedBadge: Decodable, Sendable, Identifiable, Hashable {
        var id: String
        var name: String
        var description: String
        var tier: BadgeTier
        var category: String
        var icon: String
        var earnedAt: Date
    }

    var id: String
    var username: String
    var displayName: String
    var bio: String?
    var friendStatus: FriendStatus
    var summary: Summary
    var ascents: [Ascent]
    var badges: [EarnedBadge]

    private enum CodingKeys: String, CodingKey { case id, username, displayName, bio, friendStatus, summary, ascents, badges }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decode(String.self, forKey: .displayName)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        friendStatus = try c.decode(FriendStatus.self, forKey: .friendStatus)
        summary = try c.decode(Summary.self, forKey: .summary)
        ascents = try c.decode(LossyArray<Ascent>.self, forKey: .ascents).elements
        badges = try c.decode(LossyArray<EarnedBadge>.self, forKey: .badges).elements
    }

    /// Sus cumbres agrupadas por pico (para el globo).
    var peakGroups: [PeakGroup] {
        Dictionary(grouping: ascents, by: \.peak.id).values.compactMap { list in
            let sorted = list.sorted { $0.summitedAt > $1.summitedAt }
            return sorted.first.map { PeakGroup(peak: $0.peak, ascents: sorted) }
        }
    }
}

// MARK: - Feed

enum FeedKind: String, Codable, Sendable, TolerantEnum {
    case activity, ascent, badge, challengeCompleted = "challenge_completed", unknown
    static let fallback = FeedKind.unknown
}

struct FeedBadge: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String
    var tier: BadgeTier
    var category: String
    var icon: String
}

struct FeedChallenge: Codable, Hashable, Sendable {
    var id: String
    var slug: String?
    var title: String
    var kind: String
    var badgeId: String?
    var official: Bool

    /// La misma medalla que en Logros.
    var medalIcon: String {
        if let badgeId { return "badge-\(badgeId)" }
        if official, let slug { return "challenge-\(slug)" }
        return kind == "peaks" ? "challenge-generic-peaks" : "challenge-generic-summits"
    }
}

struct FeedItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: FeedKind
    var at: Date
    var visibility: Visibility
    var actor: PublicUser
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
    var activity: Activity?
    /// Vista previa de la ruta (tramos de `[lat, lon]`), para el mapa 3D.
    var route: [[[Double]]]?
    var ascents: [Ascent]?
    var badge: FeedBadge?
    var challenge: FeedChallenge?
}

struct FeedPage: Decodable, Sendable {
    var items: [FeedItem]
    var nextBefore: Int64?

    private enum CodingKeys: String, CodingKey { case items, nextBefore }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode(LossyArray<FeedItem>.self, forKey: .items).elements.filter { $0.kind != .unknown }
        nextBefore = try c.decodeIfPresent(Int64.self, forKey: .nextBefore)
    }
}

/// Novedades para el número del icono y de la pestaña Amigos.
struct BadgeCounts: Decodable, Sendable {
    var notifications: Int
    var feed: Int
    var total: Int
}

struct FeedComment: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var body: String
    var createdAt: Date
    var author: PublicUser
}

// MARK: - Avisos

enum NotificationKind: String, Codable, Sendable, TolerantEnum {
    case friendRequest = "friend_request", friendAccepted = "friend_accepted", like, comment, challengeInvite = "challenge_invite", badge, unknown
    static let fallback = NotificationKind.unknown
}

struct AppNotification: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: NotificationKind
    var actor: PublicUser?
    var targetType: String?
    var targetId: String?
    var label: String?
    var read: Bool
    var createdAt: Date

    /// «te ha enviado una solicitud», «le ha gustado tu Aneto»…
    var text: String {
        let what = label.map { "«\($0)»" } ?? "tu salida"
        switch kind {
        case .friendRequest: return "quiere ser tu amigo"
        case .friendAccepted: return "ha aceptado tu solicitud"
        case .like: return "le ha gustado \(what)"
        case .comment: return "ha comentado \(what)"
        case .challengeInvite: return "te ha invitado a un reto"
        case .badge: return "ha conseguido un emblema"
        case .unknown: return "tiene algo para ti"
        }
    }
}

struct NotificationList: Decodable, Sendable {
    var unread: Int
    var notifications: [AppNotification]

    private enum CodingKeys: String, CodingKey { case unread, notifications }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unread = try c.decode(Int.self, forKey: .unread)
        notifications = try c.decode(LossyArray<AppNotification>.self, forKey: .notifications).elements
    }
}

/// Zona de privacidad: los demás no ven el tramo de tus rutas dentro del círculo.
struct PrivacyZone: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var lat: Double
    var lon: Double
    var radiusM: Int
}
