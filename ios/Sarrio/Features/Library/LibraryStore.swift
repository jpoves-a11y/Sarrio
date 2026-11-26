import Foundation
import Observation
import SarrioKit

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
        isSyncingHealth = true
        defer { isSyncingHealth = false }
        do {
            try await sync.syncHealth()
        } catch {
            errorMessage = "No se pudieron sincronizar los entrenos de Apple Health: \(error.localizedDescription)"
        }
        await load()
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
