import Foundation
import SarrioKit

enum APIError: Error, LocalizedError, Equatable {
    case http(status: Int, code: String?)
    case decoding(String)

    var status: Int? { if case let .http(status, _) = self { status } else { nil } }

    var errorDescription: String? {
        switch self {
        case .http(_, "username_taken"?): "Ese nombre de usuario ya está cogido."
        case .http(_, "invalid_username"?): "El usuario debe tener entre 3 y 20 caracteres: letras, números, punto o guion bajo."
        case .http(_, "invalid_display_name"?): "El nombre no puede estar vacío."
        case .http(_, "invalid_bio"?): "La bio puede tener como máximo 280 caracteres."
        case .http(_, "invalid_track"?): "La ruta del archivo no es válida."
        case .http(413, _): "La actividad es demasiado grande."
        case .http(_, "polar_not_configured"?): "La conexión con Polar aún no está activada en el servidor."
        case .http(_, "polar_revoked"?): "Polar ha retirado el acceso de Sarrio. Vuelve a conectar tu cuenta."
        case .http(_, "polar_not_connected"?): "Conecta tu cuenta de Polar en Ajustes."
        case .http(_, "polar_unavailable"?): "Polar no responde ahora mismo. Inténtalo más tarde."
        case .http(401, _): "Tu sesión ha caducado. Vuelve a iniciar sesión."
        case let .http(status, code): "Error del servidor (\(status)\(code.map { ": \($0)" } ?? ""))."
        case .decoding: "Respuesta inesperada del servidor."
        }
    }
}

/// Cliente de la API de Sarrio (Cloudflare Worker). La app nunca habla directamente con Turso.
struct APIClient: Sendable {
    let baseURL: URL
    var session: URLSession = .shared
    /// JWT de sesión, leído del Llavero en cada petición.
    var bearerToken: @Sendable () -> String? = { KeychainStore.sessionToken }

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
    nonisolated(unsafe) private static let encoder = JSONEncoder()

    private struct ErrorBody: Decodable { var error: String? }
    private struct Empty: Encodable {}

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try await send("GET", path, body: Optional<Empty>.none)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable, as type: T.Type = T.self) async throws -> T {
        try await send("POST", path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send("PATCH", path, body: body)
    }

    func delete(_ path: String) async throws {
        _ = try await raw("DELETE", path, body: Optional<Empty>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        let data = try await raw(method, path, body: body)
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw APIError.decoding(String(describing: error)) }
    }

    private func raw<B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> Data {
        // `appending(path:)` escaparía el "?": separamos la query a mano.
        let parts = path.split(separator: "?", maxSplits: 1)
        var url = baseURL.appending(path: String(parts[0]))
        if parts.count > 1, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = String(parts[1])
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = bearerToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.http(status: status, code: try? Self.decoder.decode(ErrorBody.self, from: data).error)
        }
        return data
    }

    // MARK: - Endpoints

    func peakPack(cell: String) async throws -> PeakPack {
        try await get("v1/peaks/pack/\(cell)")
    }

    func searchPeaks(_ query: String, limit: Int = 20) async throws -> [Peak] {
        struct Body: Decodable { var peaks: [Peak] }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? ""
        return try await get("v1/peaks/search?q=\(q)&limit=\(limit)", as: Body.self).peaks
    }

    /// Versión del conjunto de picos del servidor (ms), o nil si no la tiene.
    func peaksVersion() async throws -> Int64? {
        struct Body: Decodable { var version: Int64? }
        return try await get("v1/peaks/version", as: Body.self).version
    }

    struct AppleSignInRequest: Encodable {
        var identityToken: String
        var nonce: String
        var fullName: String?
    }

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        try await post("v1/auth/apple", body: request)
    }

    func me() async throws -> Me { try await get("v1/me") }

    func updateMe(_ update: ProfileUpdate) async throws -> Me { try await patch("v1/me", body: update) }

    func deleteAccount() async throws { try await delete("v1/me") }

    func user(username: String) async throws -> UserProfile {
        let name = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return try await get("v1/users/\(name)")
    }

    // MARK: Actividades y ascensiones

    func uploadActivity(_ upload: ActivityUpload) async throws -> ActivityWithAscents {
        try await post("v1/activities", body: upload)
    }

    func activities(before: Date? = nil, limit: Int = 50) async throws -> ActivityPage {
        var path = "v1/activities?limit=\(limit)"
        if let before { path += "&before=\(Int64(before.timeIntervalSince1970 * 1000))" }
        return try await get(path)
    }

    func activity(id: String) async throws -> ActivityDetail { try await get("v1/activities/\(id)") }

    func updateActivity(id: String, _ update: ActivityUpdate) async throws -> ActivityWithAscents {
        try await patch("v1/activities/\(id)", body: update)
    }

    func deleteActivity(id: String) async throws { try await delete("v1/activities/\(id)") }

    func library() async throws -> Library { try await get("v1/ascents") }

    func addAscent(_ ascent: ManualAscent) async throws -> Ascent { try await post("v1/ascents", body: ascent) }

    // MARK: Proveedores (Polar)

    struct ProviderStatus: Decodable, Sendable {
        var provider: String
        var configured: Bool
        var connected: Bool
    }

    struct ConnectResponse: Decodable, Sendable {
        var url: URL
        var callbackScheme: String
    }

    struct PolarExercise: Decodable, Sendable, Identifiable {
        var id: String
        var startTime: String
        var durationS: Double?
        var distanceM: Double?
        var sport: String?
        var hasRoute: Bool
        var imported: Bool
    }

    func providers() async throws -> [ProviderStatus] {
        struct Body: Decodable { var providers: [ProviderStatus] }
        return try await get("v1/providers", as: Body.self).providers
    }

    func polarConnectURL() async throws -> ConnectResponse {
        try await post("v1/providers/polar/connect", body: Empty())
    }

    func polarExercises() async throws -> [PolarExercise] {
        struct Body: Decodable { var exercises: [PolarExercise] }
        return try await get("v1/providers/polar/exercises", as: Body.self).exercises
    }

    /// El FIT de un entreno de Polar, tal cual.
    func polarFIT(id: String) async throws -> Data {
        try await raw("GET", "v1/providers/polar/exercises/\(id)/fit", body: Optional<Empty>.none)
    }

    func disconnectPolar() async throws { try await delete("v1/providers/polar") }

    func deleteAscent(id: String) async throws { try await delete("v1/ascents/\(id)") }

    // MARK: Emblemas y retos

    func badges() async throws -> BadgeCatalog { try await get("v1/badges") }

    enum ChallengeScope: String { case featured, joined, mine }

    func challenges(_ scope: ChallengeScope) async throws -> [Challenge] {
        try await get("v1/challenges?scope=\(scope.rawValue)", as: ChallengeList.self).challenges
    }

    func challenge(id: String) async throws -> ChallengeDetail { try await get("v1/challenges/\(id)") }

    func createChallenge(_ challenge: NewChallenge) async throws -> Challenge {
        struct Body: Decodable { var challenge: Challenge }
        return try await post("v1/challenges", body: challenge, as: Body.self).challenge
    }

    func joinChallenge(id: String) async throws {
        _ = try await raw("POST", "v1/challenges/\(id)/join", body: Empty())
    }

    func leaveChallenge(id: String) async throws { try await delete("v1/challenges/\(id)/join") }

    func deleteChallenge(id: String) async throws { try await delete("v1/challenges/\(id)") }

    // MARK: Social

    struct StatusBody: Decodable, Sendable { var status: FriendStatus }

    func friends() async throws -> FriendsList { try await get("v1/friends") }

    func searchUsers(_ query: String) async throws -> [Person] {
        struct Body: Decodable { var users: [Person] }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? ""
        return try await get("v1/users/search?q=\(q)", as: Body.self).users
    }

    func sendFriendRequest(to userId: String) async throws -> FriendStatus {
        try await post("v1/friends/\(userId)", body: Empty(), as: StatusBody.self).status
    }

    func acceptFriend(_ userId: String) async throws -> FriendStatus {
        try await post("v1/friends/\(userId)/accept", body: Empty(), as: StatusBody.self).status
    }

    func removeFriend(_ userId: String) async throws { try await delete("v1/friends/\(userId)") }

    func block(_ userId: String) async throws { _ = try await raw("POST", "v1/blocks/\(userId)", body: Empty()) }

    func unblock(_ userId: String) async throws { try await delete("v1/blocks/\(userId)") }

    func blockedUsers() async throws -> [PublicUser] {
        struct Body: Decodable { var blocked: [PublicUser] }
        return try await get("v1/blocks", as: Body.self).blocked
    }

    func report(targetType: String, targetId: String, reason: String) async throws {
        struct Body: Encodable { var targetType: String; var targetId: String; var reason: String }
        _ = try await raw("POST", "v1/reports", body: Body(targetType: targetType, targetId: targetId, reason: reason))
    }

    func feed(before: Int64? = nil) async throws -> FeedPage {
        try await get("v1/feed" + (before.map { "?before=\($0)" } ?? ""))
    }

    func like(_ itemId: String) async throws { _ = try await raw("POST", "v1/likes/feed_item/\(itemId)", body: Empty()) }

    func unlike(_ itemId: String) async throws { try await delete("v1/likes/feed_item/\(itemId)") }

    func comments(_ itemId: String) async throws -> [FeedComment] {
        struct Body: Decodable { var comments: [FeedComment] }
        return try await get("v1/comments/feed_item/\(itemId)", as: Body.self).comments
    }

    func addComment(_ itemId: String, body text: String) async throws -> FeedComment {
        struct Body: Encodable { var body: String }
        return try await post("v1/comments/feed_item/\(itemId)", body: Body(body: text))
    }

    func deleteComment(_ id: String) async throws { try await delete("v1/comments/\(id)") }

    func notifications() async throws -> NotificationList { try await get("v1/notifications") }

    func markNotificationsRead() async throws { _ = try await raw("POST", "v1/notifications/read", body: Empty()) }
}
