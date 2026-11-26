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

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
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

    func user(username: String) async throws -> PublicUser { try await get("v1/users/\(username)") }

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

    func deleteAscent(id: String) async throws { try await delete("v1/ascents/\(id)") }
}
