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
    /// Emblemas recién conseguidos que aún no se han celebrado (uno cada vez).
    var celebration: NewBadge?
    private var queue: [NewBadge] = []

    private let api: APIClient
    private var observers: [Task<Void, Never>] = []

    init(api: APIClient) {
        self.api = api
        observers.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .sarrioBadgesEarned) {
                guard let badges = note.object as? [NewBadge] else { continue }
                self?.enqueue(badges)
            }
        })
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

    private func enqueue(_ badges: [NewBadge]) {
        queue.append(contentsOf: badges.filter { b in !queue.contains(b) && celebration != b })
        if celebration == nil { next() }
        Task { await loadBadges() }
    }

    /// Pasa al siguiente emblema de la cola (o cierra).
    func next() {
        celebration = queue.isEmpty ? nil : queue.removeFirst()
    }
}
