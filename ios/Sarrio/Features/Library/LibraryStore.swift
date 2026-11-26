import Foundation
import Observation
import SarrioKit
import SwiftUI
import UIKit

/// Un pico de la biblioteca con todas sus ascensiones (la más reciente primero).
struct PeakGroup: Identifiable, Hashable {
    var peak: PeakRef
    var ascents: [Ascent]
    var id: Int64 { peak.id }
    var lastAscent: Date { ascents.first?.summitedAt ?? .distantPast }
}

/// Estado de la pestaña Cumbres: biblioteca, actividades recientes e importación.
@MainActor
@Observable
final class LibraryStore {
    enum SortOrder: String, CaseIterable, Identifiable {
        case recent, altitude, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: "Más recientes"
            case .altitude: "Más altas"
            case .name: "Nombre"
            }
        }
    }

    private(set) var library: Library?
    private(set) var activities: [Activity] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var isSyncingHealth = false
    var errorMessage: String?
    /// Resultado de la última importación manual, para enseñarlo en una hoja.
    var lastImport: ActivitySync.Outcome?
    var sortOrder: SortOrder = .recent

    private let api: APIClient
    let sync: ActivitySync
    private var changes: Task<Void, Never>?

    init(api: APIClient, sync: ActivitySync) {
        self.api = api
        self.sync = sync
        self.healthConnected = sync.healthKit.isConnected
        // Las subidas en segundo plano (Apple Health, Share Extension) avisan para recargar.
        changes = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .sarrioLibraryChanged) {
                await self?.load()
            }
        }
    }

    private(set) var healthConnected: Bool

    var peakGroups: [PeakGroup] {
        let grouped = Dictionary(grouping: library?.ascents ?? [], by: \.peak.id)
        let groups = grouped.values.compactMap { list -> PeakGroup? in
            let sorted = list.sorted { $0.summitedAt > $1.summitedAt }
            return sorted.first.map { PeakGroup(peak: $0.peak, ascents: sorted) }
        }
        switch sortOrder {
        case .recent: return groups.sorted { $0.lastAscent > $1.lastAscent }
        case .altitude: return groups.sorted { ($0.peak.ele ?? 0) > ($1.peak.ele ?? 0) }
        case .name: return groups.sorted { $0.peak.displayName.localizedStandardCompare($1.peak.displayName) == .orderedAscending }
        }
    }

    var totalElevationGain: Double { activities.compactMap(\.elevGainM).reduce(0, +) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let lib = api.library()
            async let page = api.activities(limit: 100)
            library = try await lib
            activities = try await page.activities
            await refreshProviders()
            // Satélite y relieve de tus cumbres guardados en el iPhone (con wifi, una vez al día)
            MapPrefetcher.shared.prefetch(peaks: peakGroups.sorted { $0.lastAscent > $1.lastAscent }.map(\.peak))
        } catch {
            if library == nil { errorMessage = error.localizedDescription }
        }
    }

    func importFile(at url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            lastImport = try await sync.importFile(at: url)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Archivos que ha dejado la Share Extension.
    func processSharedInbox() async {
        guard !SharedInbox.pendingFiles().isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        let result = await sync.processSharedInbox()
        if result.outcomes.count == 1 { lastImport = result.outcomes[0] }
        if !result.failures.isEmpty { errorMessage = result.failures.joined(separator: "\n") }
        await load()
    }

    func connectHealth() async {
        do {
            try await sync.healthKit.requestAuthorization()
            healthConnected = true
            AppServices.shared.startHealthObserver()
            await syncHealth()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncHealth() async {
        guard healthConnected else { return }
        // Con el iPhone bloqueado (o aún desbloqueándose) Salud no deja leer: se espera al desbloqueo
        guard UIApplication.shared.isProtectedDataAvailable else {
            pendingHealthSync = true
            return
        }
        pendingHealthSync = false
        isSyncingHealth = true
        defer { isSyncingHealth = false }
        await withBackgroundTime {
            do {
                try await self.sync.syncHealth(progress: self.report)
            } catch where HealthKitService.isLockedError(error) {
                // Se bloqueó a mitad: sigue al desbloquear, con lo que falte
                self.pendingHealthSync = true
                self.clearProgress(of: .health)
            } catch {
                self.clearProgress(of: .health)
                if UIApplication.shared.applicationState == .active {
                    self.errorMessage = "No se pudieron sincronizar los entrenos de Apple Health: \(error.localizedDescription)"
                }
            }
        }
        await load()
    }

    // MARK: Progreso

    /// La sincronización en curso (o la que acaba de terminar, unos segundos).
    private(set) var syncProgress: SyncProgress?

    private var report: ActivitySync.ProgressHandler {
        { [weak self] progress in
            guard let self else { return }
            withAnimation(Theme.Motion.spring) { self.syncProgress = progress }
            if progress.phase == .done {
                // El resumen se queda unos segundos y luego se va
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(progress.total == 0 ? 1.5 : 6))
                    guard let self, self.syncProgress == progress else { return }
                    withAnimation(Theme.Motion.spring) { self.syncProgress = nil }
                }
            }
        }
    }

    private func clearProgress(of source: SyncProgress.Source) {
        guard syncProgress?.source == source else { return }
        withAnimation(Theme.Motion.spring) { syncProgress = nil }
    }

    /// Pide a iOS tiempo para terminar aunque se bloquee el iPhone o se cambie de app. Si no le da
    /// tiempo, programa una tarea en segundo plano que sigue después con lo que falte.
    private func withBackgroundTime(_ work: @MainActor () async -> Void) async {
        let box = BackgroundTaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "sarrio-sync") {
            MainActor.assumeIsolated {
                BackgroundSync.schedule()
                if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id) }
                box.id = .invalid
            }
        }
        await work()
        if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id) }
        box.id = .invalid
    }

    /// Hay una sincronización con Salud pendiente de que se desbloquee el iPhone.
    private(set) var pendingHealthSync = false

    // MARK: Polar

    /// Polar: conectado y si el servidor tiene Polar configurado.
    private(set) var polarConnected = false
    private(set) var polarAvailable = false
    private(set) var isSyncingPolar = false
    private let polarConnector = PolarConnector()

    func refreshProviders() async {
        guard let polar = try? await api.providers().first(where: { $0.provider == "polar" }) else { return }
        polarConnected = polar.connected
        polarAvailable = polar.configured
    }

    func connectPolar() async {
        do {
            let target = try await api.polarConnectURL()
            guard try await polarConnector.connect(url: target.url, callbackScheme: target.callbackScheme) else { return }
            polarConnected = true
            await syncPolar()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncPolar() async {
        guard polarConnected else { return }
        isSyncingPolar = true
        defer { isSyncingPolar = false }
        await withBackgroundTime {
            do {
                try await self.sync.syncPolar(progress: self.report)
            } catch let error as APIError where error == .http(status: 409, code: "polar_revoked") || error == .http(status: 409, code: "polar_not_connected") {
                self.polarConnected = false
                self.clearProgress(of: .polar)
                self.errorMessage = error.localizedDescription
            } catch {
                self.clearProgress(of: .polar)
                // Cortada por iOS en segundo plano: la tarea programada sigue con lo que falte
                if UIApplication.shared.applicationState == .active {
                    self.errorMessage = "No se pudieron traer los entrenos de Polar: \(error.localizedDescription)"
                } else {
                    BackgroundSync.schedule()
                }
            }
        }
        await load()
    }

    func disconnectPolar() async {
        do {
            try await api.disconnectPolar()
            polarConnected = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectHealth() {
        sync.healthKit.disconnect()
        healthConnected = false
    }

    func delete(_ activity: Activity) async {
        do {
            try await api.deleteActivity(id: activity.id)
            activities.removeAll { $0.id == activity.id }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ activity: Activity, visibility: Visibility) async {
        do {
            let updated = try await api.updateActivity(id: activity.id, ActivityUpdate(visibility: visibility))
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = updated.activity
                activities[index].ascents = updated.ascents
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Identificador de la tarea de segundo plano en curso (lo comparten la sincronización y su caducidad).
private final class BackgroundTaskBox: @unchecked Sendable {
    var id = UIBackgroundTaskIdentifier.invalid
}
