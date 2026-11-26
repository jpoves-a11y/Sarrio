import Foundation
import SarrioKit

extension Notification.Name {
    /// Se han subido actividades nuevas: la biblioteca debe recargarse.
    static let sarrioLibraryChanged = Notification.Name("sarrio.libraryChanged")
}

/// Convierte archivos y entrenos de Apple Health en actividades subidas a la API,
/// con las cumbres detectadas en el propio iPhone.
actor ActivitySync {
    struct Outcome: Sendable, Identifiable {
        var id: String { activity.id }
        var activity: Activity
        var ascents: [Ascent]
        /// `false` si esa actividad ya estaba subida.
        var isNew: Bool
    }

    enum SyncError: LocalizedError {
        case unsupportedFile(String)
        case noTrack

        var errorDescription: String? {
            switch self {
            case let .unsupportedFile(ext): "Sarrio no puede leer archivos .\(ext). Usa GPX, FIT o TCX."
            case .noTrack: "El archivo no tiene ruta GPS."
            }
        }
    }

    private let api: APIClient
    private let peakPackStore: PeakPackStore
    let healthKit: HealthKitService
    private var healthSyncRunning = false

    init(api: APIClient, peakPackStore: PeakPackStore, healthKit: HealthKitService) {
        self.api = api
        self.peakPackStore = peakPackStore
        self.healthKit = healthKit
    }

    // MARK: - Archivos

    /// Importa un archivo elegido por el usuario o abierto desde otra app.
    func importFile(at url: URL) async throws -> Outcome {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try await importFile(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension)
    }

    func importFile(data: Data, name: String?, fileExtension: String) async throws -> Outcome {
        let format = TrackFileFormat(fileExtension: fileExtension) ?? TrackFileFormat(sniffing: data)
        guard let format else { throw SyncError.unsupportedFile(fileExtension) }
        let parsed: ParsedTrack
        do { parsed = try TrackFile.parse(data: data, format: format) } catch TrackParseError.noPoints { throw SyncError.noTrack }
        let title = parsed.name ?? name.flatMap { $0.isEmpty ? nil : $0 }
        return try await upload(parsed, source: .file, externalId: "file:" + TrackFile.fingerprint(data), title: title)
    }

    /// Procesa lo que haya dejado la Share Extension. Los archivos que fallan se descartan (y se informa).
    func processSharedInbox() async -> (outcomes: [Outcome], failures: [String]) {
        var outcomes: [Outcome] = []
        var failures: [String] = []
        for file in SharedInbox.pendingFiles() {
            do {
                let data = try Data(contentsOf: file)
                outcomes.append(try await importFile(data: data, name: SharedInbox.originalName(of: file), fileExtension: file.pathExtension))
                SharedInbox.remove(file)
            } catch is URLError {
                // Sin conexión: se deja en la bandeja para la próxima vez.
                break
            } catch {
                failures.append("\(SharedInbox.originalName(of: file)): \(error.localizedDescription)")
                SharedInbox.remove(file)
            }
        }
        if !outcomes.isEmpty { notifyChange() }
        return (outcomes, failures)
    }

    // MARK: - Apple Health

    /// Sube los entrenos nuevos de Apple Health. Seguro de llamar varias veces a la vez.
    @discardableResult
    func syncHealth() async throws -> [Outcome] {
        guard HealthKitService.isAvailable, healthKit.isConnected, !healthSyncRunning else { return [] }
        healthSyncRunning = true
        defer { healthSyncRunning = false }

        var outcomes: [Outcome] = []
        while true {
            let batch = try await healthKit.newWorkouts()
            for workout in batch.workouts {
                let parsed = ParsedTrack(name: nil, points: workout.points, sport: workout.sport)
                outcomes.append(try await upload(
                    parsed,
                    source: .healthkit,
                    externalId: workout.uuid.uuidString,
                    title: nil,
                    startDate: workout.start,
                    duration: workout.end.timeIntervalSince(workout.start),
                    distance: workout.distance,
                    elevationGain: workout.elevationGain
                ))
            }
            healthKit.commit(batch)
            if !batch.hasMore { break }
        }
        if outcomes.contains(where: \.isNew) { notifyChange() }
        return outcomes
    }

    // MARK: - Polar

    private var polarSyncRunning = false

    /// Sube los entrenos de Polar con ruta que aún no estén en Sarrio (Polar da los últimos 30 días).
    @discardableResult
    func syncPolar() async throws -> [Outcome] {
        guard !polarSyncRunning else { return [] }
        polarSyncRunning = true
        defer { polarSyncRunning = false }

        var outcomes: [Outcome] = []
        for exercise in try await api.polarExercises() where exercise.hasRoute && !exercise.imported {
            let data = try await api.polarFIT(id: exercise.id)
            let parsed: ParsedTrack
            do { parsed = try FITParser.parse(data: data) } catch { continue } // sin GPS utilizable
            guard parsed.points.count >= 2 else { continue }
            outcomes.append(try await upload(
                parsed,
                source: .polar,
                externalId: exercise.id,
                title: nil,
                duration: exercise.durationS,
                distance: exercise.distanceM
            ))
        }
        if outcomes.contains(where: \.isNew) { notifyChange() }
        return outcomes
    }

    // MARK: - Subida

    private func upload(
        _ parsed: ParsedTrack,
        source: ActivityUpload.Source,
        externalId: String,
        title: String?,
        startDate: Date? = nil,
        duration: TimeInterval? = nil,
        distance: Double? = nil,
        elevationGain: Double? = nil
    ) async throws -> Outcome {
        guard parsed.points.count >= 2 else { throw SyncError.noTrack }
        let summits = try await peakPackStore.detectSummits(in: parsed.points)
        let body = ActivityUpload(
            track: parsed,
            summits: summits,
            source: source,
            externalId: externalId,
            title: title,
            startDate: startDate,
            duration: duration,
            distance: distance,
            elevationGain: elevationGain
        )
        let response = try await api.uploadActivity(body)
        return Outcome(activity: response.activity, ascents: response.ascents, isNew: response.created ?? true)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sarrioLibraryChanged, object: nil)
    }
}
