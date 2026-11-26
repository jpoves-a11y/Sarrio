import AuthenticationServices
import UIKit

/// Inicio de sesión con Polar Flow en una hoja segura del sistema (ASWebAuthenticationSession).
/// El backend recibe el código de Polar y vuelve a la app con `sarrio://polar?status=…`.
@MainActor
final class PolarConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum ConnectError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed("already_linked"): "Esa cuenta de Polar ya está enlazada a otro usuario de Sarrio."
            case .failed("not_configured"): "La conexión con Polar aún no está activada en el servidor."
            case let .failed(reason): "No se pudo conectar con Polar (\(reason))."
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    /// `true` si se conectó; `false` si el usuario cerró la hoja.
    func connect(url: URL, callbackScheme: String) async throws -> Bool {
        let callback: URL? = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        session = nil
        guard let callback else { return false }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let status = items.first { $0.name == "status" }?.value
        switch status {
        case "connected": return true
        case "cancelled": return false
        default: throw ConnectError.failed(items.first { $0.name == "reason" }?.value ?? "desconocido")
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
