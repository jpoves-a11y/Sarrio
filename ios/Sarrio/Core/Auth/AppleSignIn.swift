import CryptoKit
import Foundation

/// Nonce para Sign in with Apple: la app envía a Apple el SHA-256 y al backend el valor en claro.
struct AppleSignInNonce {
    let raw: String
    var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func make(length: Int = 32) -> AppleSignInNonce {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return AppleSignInNonce(raw: String((0..<length).map { _ in charset.randomElement(using: &generator)! }))
    }
}
