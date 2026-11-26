import Foundation
import SarrioKit

/// Picos para detectar cumbres en el iPhone, por celda geohash de 4 caracteres.
///
/// 1. **La copia de la app** (`peaks.tsv`, ver `PeakBundle`): Pirineos, Sierra Nevada, Picos de
///    Europa, Sistema Central y Alpes, al instante y sin conexión.
/// 2. **El servidor** (`GET /v1/peaks/pack/:cell`), con caché en disco de 30 días: para las zonas
///    que la copia no cubre, o todas si el servidor tiene un conjunto más nuevo que la copia.
///    Si la red falla en una zona cubierta, se usa la copia igualmente.
actor PeakPackStore {
    private let api: APIClient
    private let directory: URL
    private var memory: [String: [Peak]] = [:]
    private let maxAge: TimeInterval = 30 * 24 * 3600
    private var bundle: PeakBundle?
    private var bundleLoaded = false
    /// nil: aún no se ha preguntado; se pregunta una vez por arranque.
    private var serverIsNewer: Bool?

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
        let bundled = loadBundle()
        if let bundled, bundled.covers(cell) {
            let serverNewer = await isServerNewer(than: bundled)
            if !serverNewer {
                let peaks = bundled.peaks(in: cell)
                memory[cell] = peaks
                return peaks
            }
        }
        do {
            let peaks = try await serverPeaks(in: cell)
            memory[cell] = peaks
            return peaks
        } catch {
            // Sin red: si la copia cubre la zona, mejor sus picos que ninguno
            guard let bundled, bundled.covers(cell) else { throw error }
            return bundled.peaks(in: cell)
        }
    }

    // MARK: - Búsqueda

    /// Picos por nombre: primero en la copia de la app (al instante y sin red); si da pocos
    /// resultados, también en el servidor (zonas que la copia no cubre).
    func search(_ query: String, preferred: Set<Int64> = [], limit: Int = 20) async -> [Peak] {
        var results = loadBundle()?.search(query, limit: limit, preferred: preferred) ?? []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if results.count < 5, q.count >= 3, let remote = try? await api.searchPeaks(q, limit: limit) {
            let known = Set(results.map(\.id))
            results += remote.filter { !known.contains($0.id) }
        }
        return Array(results.prefix(limit))
    }

    // MARK: - Copia de la app

    private func loadBundle() -> PeakBundle? {
        if bundleLoaded { return bundle }
        bundleLoaded = true
        guard let url = Bundle.main.url(forResource: "peaks", withExtension: "tsv"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        bundle = try? PeakBundle(data: data)
        return bundle
    }

    /// ¿Tiene el servidor un conjunto de picos más nuevo que la copia? Si no se puede saber, no.
    private func isServerNewer(than bundled: PeakBundle) async -> Bool {
        if let serverIsNewer { return serverIsNewer }
        var newer = false
        if let local = bundled.version, let remote = try? await api.peaksVersion() {
            newer = remote > local
        }
        serverIsNewer = newer
        return newer
    }

    // MARK: - Servidor

    private func serverPeaks(in cell: String) async throws -> [Peak] {
        let file = directory.appending(path: "\(cell).json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge,
           let data = try? Data(contentsOf: file),
           let pack = try? JSONDecoder().decode(PeakPack.self, from: data) {
            return pack.peaks
        }
        let pack = try await api.peakPack(cell: cell)
        if let data = try? JSONEncoder().encode(pack) { try? data.write(to: file, options: .atomic) }
        return pack.peaks
    }
}
