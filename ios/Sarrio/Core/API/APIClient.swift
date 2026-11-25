import Foundation
import SarrioKit

enum APIError: Error, LocalizedError {
    case http(status: Int, body: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case let .http(status, body): "Error \(status) del servidor: \(body)"
        case let .decoding(error): "Respuesta inesperada del servidor: \(error.localizedDescription)"
        }
    }
}

/// Cliente de la API de Sarrio (Cloudflare Worker). La app nunca habla directamente con Turso.
struct APIClient: Sendable {
    let baseURL: URL
    var session: URLSession = .shared
    /// JWT de sesión propio (se rellena en la fase 2 tras Sign in with Apple).
    var bearerToken: (@Sendable () -> String?)? = nil

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        if let token = bearerToken?() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw APIError.decoding(error) }
    }

    func peakPack(cell: String) async throws -> PeakPack {
        try await get("v1/peaks/pack/\(cell)")
    }
}
