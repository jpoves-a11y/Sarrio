import Foundation
import SarrioKit

/// Descarga y cachea en disco los paquetes de picos por celda geohash de 4 caracteres,
/// para detectar cumbres en el propio iPhone (también sin conexión).
actor PeakPackStore {
    private let api: APIClient
    private let directory: URL
    private var memory: [String: [Peak]] = [:]
    private let maxAge: TimeInterval = 30 * 24 * 3600

    init(api: APIClient) {
        self.api = api
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "peak-packs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Picos candidatos para un track: todas las celdas que cubre su caja (más un margen).
    func candidates(for track: [TrackPoint]) async throws -> [Peak] {
        guard let box = BoundingBox(points: track)?.expanded(byMeters: 200) else { return [] }
        var result: [Peak] = []
        for cell in Geo.geohashCells(covering: box, precision: 4) {
            result += try await peaks(in: cell)
        }
        return result
    }

    /// Atajo completo: track → cumbres detectadas.
    func detectSummits(in track: [TrackPoint], detector: PeakDetector = PeakDetector()) async throws -> [DetectedSummit] {
        detector.detect(track: track, candidates: try await candidates(for: track))
    }

    func peaks(in cell: String) async throws -> [Peak] {
        if let cached = memory[cell] { return cached }
        let file = directory.appending(path: "\(cell).json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge,
           let data = try? Data(contentsOf: file),
           let pack = try? JSONDecoder().decode(PeakPack.self, from: data) {
            memory[cell] = pack.peaks
            return pack.peaks
        }
        let pack = try await api.peakPack(cell: cell)
        if let data = try? JSONEncoder().encode(pack) { try? data.write(to: file, options: .atomic) }
        memory[cell] = pack.peaks
        return pack.peaks
    }
}
