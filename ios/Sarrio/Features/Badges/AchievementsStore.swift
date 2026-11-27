import Foundation
import Observation
import SwiftUI

/// Emblemas y retos: el catálogo con mi estado, los retos y la cola de celebraciones.
@MainActor
@Observable
final class AchievementsStore {
    private(set) var catalog: BadgeCatalog?
    private(set) var featured: [Challenge] = []
    private(set) var mine: [Challenge] = []
    private(set) var isLoadingChallenges = false
    var errorMessage: String?
    /// Lo que se celebra tras una subida (sus cumbres y luego sus emblemas), uno detrás de otro en una
    /// sola pantalla. La cola se guarda: si la salida llegó con la app cerrada, se celebra al abrirla.
    var isCelebrating = false
    private(set) var pending: [CelebrationItem] = []
    private(set) var index = 0
    var current: CelebrationItem? { pending.indices.contains(index) ? pending[index] : nil }
    private static let pendingKey = "pendingCelebrations"

    private let api: APIClient
    private var observers: [Task<Void, Never>] = []

    init(api: APIClient) {
        self.api = api
        observers.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .sarrioOutingCelebrated) {
                guard let celebration = note.object as? OutingCelebration else { continue }
                var items: [CelebrationItem] = []
                if let summits = celebration.summits { items.append(.summits(summits)) }
                items += celebration.badges.map { .badge($0) }
                self?.enqueue(items)
            }
        })
        // Lo que quedó sin ver (llegó en segundo plano o se cerró la app a medias)
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([CelebrationItem].self, from: data), !saved.isEmpty {
            pending = saved
            isCelebrating = true
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        }
        // Cualquier subida cambia el progreso de los retos
        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .sarrioLibraryChanged) {
                await self?.refresh()
            }
        })
    }

    var badges: [Badge] { catalog?.badges ?? [] }
    var earned: [Badge] { badges.filter(\.isEarned).sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) } }

    /// Categorías en el orden del catálogo.
    var categories: [(name: String, badges: [Badge])] {
        var order: [String] = []
        var groups: [String: [Badge]] = [:]
        for badge in badges {
            if groups[badge.category] == nil { order.append(badge.category) }
            groups[badge.category, default: []].append(badge)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// Los que están más cerca de conseguirse.
    var closest: [Badge] {
        badges.filter { !$0.isEarned && ($0.progress?.fraction ?? 0) > 0 }
            .sorted { ($0.progress?.fraction ?? 0) > ($1.progress?.fraction ?? 0) }
    }

    func loadBadges() async {
        do { catalog = try await api.badges() } catch { if catalog == nil { errorMessage = error.localizedDescription } }
    }

    func loadChallenges() async {
        isLoadingChallenges = true
        defer { isLoadingChallenges = false }
        do {
            // Todos los retos están siempre activos: oficiales y los míos
            async let f = api.challenges(.featured)
            async let m = api.challenges(.mine)
            (featured, mine) = try await (f, m)
        } catch {
            if featured.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    func refresh() async {
        async let b: Void = loadBadges()
        async let c: Void = loadChallenges()
        _ = await (b, c)
    }

    func create(_ challenge: NewChallenge) async throws -> Challenge {
        let created = try await api.createChallenge(challenge)
        await loadChallenges()
        return created
    }

    func delete(_ challenge: Challenge) async {
        do {
            try await api.deleteChallenge(id: challenge.id)
            await loadChallenges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Celebración

    /// Los que llegan durante una celebración se añaden al final: nunca interrumpen al que se está viendo.
    private func enqueue(_ items: [CelebrationItem]) {
        if !isCelebrating {
            pending = []
            index = 0
        }
        let new = items.filter { item in !pending.contains { $0.id == item.id } }
        guard !new.isEmpty else { return }
        pending.append(contentsOf: new)
        isCelebrating = true
        save()
        if new.contains(where: { if case .badge = $0 { true } else { false } }) {
            Task { await loadBadges() }
        }
    }

    /// Pasa al siguiente; tras el último, cierra.
    func advance() {
        if index + 1 < pending.count {
            index += 1
        } else {
            isCelebrating = false
            pending = []
            index = 0
        }
        save()
    }

    /// Guarda lo que queda por ver.
    private func save() {
        let rest = pending.indices.contains(index) ? Array(pending[index...]) : []
        if !rest.isEmpty, let data = try? JSONEncoder().encode(rest) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        }
    }
}
