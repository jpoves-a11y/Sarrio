import Foundation
import SarrioKit

extension Notification.Name {
    /// Se han subido actividades nuevas: la biblioteca debe recargarse.
    static let sarrioLibraryChanged = Notification.Name("sarrio.libraryChanged")
    /// Una subida trae algo que celebrar: sus cumbres y sus emblemas (`object`: `OutingCelebration`).
    static let sarrioOutingCelebrated = Notification.Name("sarrio.outingCelebrated")
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

    /// Avisa del progreso (en el hilo principal).
    typealias ProgressHandler = @MainActor @Sendable (SyncProgress) -> Void

    /// Sube los entrenos nuevos de Apple Health. Seguro de llamar varias veces a la vez.
    @discardableResult
    func syncHealth(progress report: ProgressHandler? = nil) async throws -> [Outcome] {
        guard HealthKitService.isAvailable, healthKit.isConnected, !healthSyncRunning else { return [] }
        healthSyncRunning = true
        defer { healthSyncRunning = false }

        var progress = SyncProgress(source: .health)
        await report?(progress)
        let sports = try await healthKit.pendingSports()
        progress.begin(total: sports.count, sports: sports)
        await report?(progress)

        var outcomes: [Outcome] = []
        while progress.phase != .done {
            let batch = try await healthKit.newWorkouts()
            for workout in batch.workouts {
                progress.current = "\(workout.sport.title) · \(workout.start.formatted(.dateTime.day().month(.abbreviated).year()))"
                await report?(progress)
                let parsed = ParsedTrack(name: nil, points: workout.points, sport: workout.sport)
                let outcome = try await upload(
                    parsed,
                    source: .healthkit,
                    externalId: workout.uuid.uuidString,
                    title: nil,
                    startDate: workout.start,
                    duration: workout.end.timeIntervalSince(workout.start),
                    distance: workout.distance,
                    elevationGain: workout.elevationGain
                )
                outcomes.append(outcome)
                progress.finishItem(outcome)
            }
            // Los entrenos sin GPS del lote también cuentan como procesados
            progress.processed = min(progress.total, progress.processed + batch.scanned - batch.workouts.count)
            healthKit.commit(batch)
            if !batch.hasMore { break }
            await report?(progress)
        }
        progress.processed = progress.total
        progress.phase = .done
        progress.current = nil
        await report?(progress)
        if outcomes.contains(where: \.isNew) { notifyChange() }
        return outcomes
    }

    // MARK: - Polar

    private var polarSyncRunning = false

    /// Sube los entrenos de Polar con ruta que aún no estén en Sarrio (Polar da los últimos 30 días).
    /// Si se interrumpe (iOS suspende la app), la próxima vez sigue con los que falten.
    @discardableResult
    func syncPolar(progress report: ProgressHandler? = nil) async throws -> [Outcome] {
        guard !polarSyncRunning else { return [] }
        polarSyncRunning = true
        defer { polarSyncRunning = false }

        var progress = SyncProgress(source: .polar)
        await report?(progress)
        // Con ruta, o sin ella si es de montaña (se guarda con sus cifras)
        let pending = try await api.polarExercises().filter {
            !$0.imported && ($0.hasRoute || SportType(polarSport: $0.sport).isMountain)
        }
        progress.begin(total: pending.count, sports: pending.map { SportType(polarSport: $0.sport) })
        await report?(progress)

        var outcomes: [Outcome] = []
        for exercise in pending {
            try Task.checkCancellation()
            let sport = SportType(polarSport: exercise.sport)
            progress.current = "\(sport.title) · \(Self.polarDate(exercise.startTime))"
            await report?(progress)
            var outcome: Outcome?
            let fit: Data? = exercise.hasRoute ? try await api.polarFIT(id: exercise.id) : nil
            if let fit, let parsed = try? FITParser.parse(data: fit), parsed.points.count >= 2 {
                var track = parsed
                if track.sport == nil || track.sport == .other { track.sport = sport }
                outcome = try await upload(
                    track,
                    source: .polar,
                    externalId: exercise.id,
                    title: nil,
                    duration: exercise.durationS,
                    distance: exercise.distanceM
                )
            } else if sport.isMountain {
                outcome = try await upload(
                    ParsedTrack(points: [], sport: sport),
                    source: .polar,
                    externalId: exercise.id,
                    title: nil,
                    startDate: Self.polarStart(exercise.startTime),
                    duration: exercise.durationS,
                    distance: exercise.distanceM,
                    sport: sport
                )
            }
            if let outcome { outcomes.append(outcome) }
            progress.finishItem(outcome)
            await report?(progress)
        }
        progress.phase = .done
        progress.current = nil
        await report?(progress)
        if outcomes.contains(where: \.isNew) { notifyChange() }
        return outcomes
    }

    /// «2026-07-14T07:00:00» (hora local de Polar) → fecha.
    private static func polarStart(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(raw.prefix(19)))
    }

    private static func polarDate(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = formatter.date(from: String(raw.prefix(19))) else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated))
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
        elevationGain: Double? = nil,
        sport: SportType? = nil
    ) async throws -> Outcome {
        // Sin ruta solo se guardan las salidas de montaña (con sus cifras, sin mapa ni cumbres)
        let sport = sport ?? parsed.sport
        guard parsed.points.count >= 2 || sport?.isMountain == true else { throw SyncError.noTrack }
        let summits = parsed.points.count >= 2 ? try await peakPackStore.detectSummits(in: parsed.points) : []
        let body = ActivityUpload(
            track: parsed,
            summits: summits,
            source: source,
            externalId: externalId,
            sport: sport,
            title: title,
            startDate: startDate,
            duration: duration,
            distance: distance,
            elevationGain: elevationGain
        )
        let response = try await api.uploadActivity(body)
        // Cumbres: siempre al importar un archivo; de Salud o Polar, solo salidas recientes (no todo
        // el historial en la primera sincronización)
        let created = response.created ?? true
        let recent = Date.now.timeIntervalSince(response.activity.startAt) < 7 * 86_400
        var celebrated: SummitCelebration?
        if created, !response.ascents.isEmpty, source == .file || source == .manual || recent {
            let step = max(1, parsed.points.count / 300)
            let route = stride(from: 0, to: parsed.points.count, by: step).map {
                SummitCelebration.Point(lat: parsed.points[$0].latitude, lon: parsed.points[$0].longitude)
            }
            celebrated = SummitCelebration(
                activityId: response.activity.id,
                title: response.activity.displayTitle,
                date: response.activity.startAt,
                ascents: response.ascents,
                route: route
            )
        }
        let badges = response.newBadges ?? []
        if celebrated != nil || !badges.isEmpty {
            let celebration = OutingCelebration(summits: celebrated, badges: badges)
            await MainActor.run { NotificationCenter.default.post(name: .sarrioOutingCelebrated, object: celebration) }
        }
        return Outcome(activity: response.activity, ascents: response.ascents, isNew: response.created ?? true)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sarrioLibraryChanged, object: nil)
    }
}
