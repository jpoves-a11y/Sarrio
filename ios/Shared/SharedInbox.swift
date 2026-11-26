import Foundation

/// Bandeja de archivos compartida entre la app y la Share Extension (contenedor del App Group).
/// La extensión deja ahí los GPX/FIT/TCX y la app los procesa al abrirse.
enum SharedInbox {
    static let supportedExtensions: Set<String> = ["gpx", "fit", "tcx"]

    /// `group.<bundle id>`, definido en el Info.plist de ambos targets.
    static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "SarrioAppGroup") as? String
    }

    static var directory: URL? {
        guard let appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = container.appending(path: "Inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copia un archivo a la bandeja con un nombre único (conserva la extensión).
    @discardableResult
    static func add(fileAt source: URL) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let ext = source.pathExtension.lowercased()
        let base = source.deletingPathExtension().lastPathComponent
        let destination = directory.appending(path: "\(UUID().uuidString.prefix(8))-\(base).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func pendingFiles() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
        else { return [] }
        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Nombre original, sin el prefijo único.
    static func originalName(of url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count > 9, name[name.index(name.startIndex, offsetBy: 8)] == "-" else { return name }
        return String(name.dropFirst(9))
    }
}
