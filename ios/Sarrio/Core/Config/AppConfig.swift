import Foundation

/// Valores leídos del Info.plist, que a su vez salen de `Config.xcconfig`.
enum AppConfig {
    static var apiBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SarrioAPIBaseURL") as? String,
              let url = URL(string: raw), !raw.isEmpty else {
            return URL(string: "http://localhost:8787")!
        }
        return url
    }
}
