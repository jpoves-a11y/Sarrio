import Foundation

/// Formatos de archivo de actividad que Sarrio sabe leer.
public enum TrackFileFormat: String, Sendable, CaseIterable {
    case gpx, fit, tcx

    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    /// Detecta el formato por el contenido (útil cuando el archivo llega sin extensión).
    public init?(sniffing data: Data) {
        if data.count >= 12, data[data.startIndex + 8 ..< data.startIndex + 12].elementsEqual(Array(".FIT".utf8)) {
            self = .fit
            return
        }
        let head = String(decoding: data.prefix(1024), as: UTF8.self)
        if head.contains("<gpx") { self = .gpx } else if head.contains("<TrainingCenterDatabase") { self = .tcx } else { return nil }
    }
}

public enum TrackFile {
    /// Lee un archivo de actividad. Si no se indica el formato, se deduce del contenido.
    public static func parse(data: Data, format: TrackFileFormat? = nil) throws -> ParsedTrack {
        guard let format = format ?? TrackFileFormat(sniffing: data) else {
            throw TrackParseError.unsupportedFormat("desconocido")
        }
        switch format {
        case .gpx: return try GPXParser.parse(data: data)
        case .fit: return try FITParser.parse(data: data)
        case .tcx: return try TCXParser.parse(data: data)
        }
    }

    /// Huella estable del archivo (FNV-1a de 64 bits), para no subir dos veces el mismo.
    public static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash) + "-\(data.count)"
    }
}
