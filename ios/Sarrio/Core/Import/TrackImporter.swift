import Foundation
import SarrioKit

/// Importa archivos de actividad. GPX en la fase 1; FIT/TCX en la fase 3 (Garmin FIT SDK).
enum TrackImporter {
    enum ImportError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            if case let .unsupported(ext) = self { return "Formato .\(ext) aún no soportado" }
            return nil
        }
    }

    static func parse(fileAt url: URL) throws -> ParsedTrack {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case "gpx": return try GPXParser.parse(data: data)
        default: throw ImportError.unsupported(url.pathExtension)
        }
    }
}
