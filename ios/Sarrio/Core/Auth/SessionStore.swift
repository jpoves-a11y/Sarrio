import AuthenticationServices
import Foundation
import Observation

/// Estado de sesión: Sign in with Apple → `POST /v1/auth/apple` → JWT propio en el Llavero.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(Me)
    }

    private(set) var state: State = KeychainStore.sessionToken == nil ? .signedOut : .loading
    var errorMessage: String?
    private let api: APIClient
    private var pendingNonce: AppleSignInNonce?

    init(api: APIClient) {
        self.api = api
    }

    var me: Me? { if case let .signedIn(me) = state { me } else { nil } }

    /// Al arrancar: si hay token, carga el perfil (y cierra sesión si ha caducado).
    func restore() async {
        guard KeychainStore.sessionToken != nil else { state = .signedOut; return }
        do {
            state = .signedIn(try await api.me())
        } catch let error as APIError where error.status == 401 || error.status == 404 {
            signOut()
        } catch {
            // Sin conexión: mantenemos la sesión; se reintentará.
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    /// Configura la petición de Apple (alcance + nonce).
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.make()
        pendingNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = nonce.hashed
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingNonce else {
                errorMessage = "No se pudo completar el inicio de sesión con Apple."
                return
            }
            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            }.flatMap { $0.isEmpty ? nil : $0 }
            do {
                let response = try await api.signInWithApple(
                    .init(identityToken: identityToken, nonce: nonce.raw, fullName: fullName)
                )
                KeychainStore.setSessionToken(response.token)
                state = .signedIn(response.user)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func update(_ update: ProfileUpdate) async throws {
        state = .signedIn(try await api.updateMe(update))
    }

    /// Foto nueva (o ninguna): se ve al instante en toda la app.
    func setAvatar(_ jpeg: Data?) async throws {
        guard var me else { return }
        if let jpeg {
            me.avatarKey = try await api.uploadAvatar(jpeg)
        } else {
            try await api.deleteAvatar()
            me.avatarKey = nil
        }
        state = .signedIn(me)
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        signOut()
    }

    func signOut() {
        KeychainStore.setSessionToken(nil)
        state = .signedOut
    }
}
