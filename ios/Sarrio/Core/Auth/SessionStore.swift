import Foundation
import Observation

/// Estado de sesión. En la fase 2 se conecta a Sign in with Apple → `POST /v1/auth/apple` → JWT en Keychain.
@MainActor
@Observable
final class SessionStore {
    private(set) var isSignedIn = false
    private(set) var username: String?

    /// Solo para desarrollo hasta que exista el endpoint de autenticación.
    func continueAsGuest() {
        username = "invitado"
        isSignedIn = true
    }

    func signOut() {
        username = nil
        isSignedIn = false
    }
}
