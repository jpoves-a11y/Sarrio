import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Estado social: el feed, los avisos y los amigos.
@MainActor
@Observable
final class SocialStore {
    private(set) var items: [FeedItem] = []
    private(set) var nextBefore: Int64?
    private(set) var isLoading = false
    private(set) var loadedOnce = false
    private(set) var notifications: [AppNotification] = []
    private(set) var unread = 0
    private(set) var friends: FriendsList?
    /// Novedades (avisos sin leer + lo nuevo de mis amigos): el número de la pestaña y del icono.
    private(set) var badgeTotal = 0
    var errorMessage: String?

    private let api: APIClient
    private var observer: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
        // Mis subidas también aparecen en el feed
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .sarrioLibraryChanged) {
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        do {
            async let page = api.feed()
            async let notes = api.notifications()
            async let list = api.friends()
            let (p, n, f) = try await (page, notes, list)
            items = p.items
            nextBefore = p.nextBefore
            notifications = n.notifications
            unread = n.unread
            friends = f
            errorMessage = nil
            await refreshBadge()
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    func loadMore() async {
        guard let before = nextBefore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await api.feed(before: before) {
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextBefore = page.nextBefore
        }
    }

    func refreshFriends() async {
        if let f = try? await api.friends() { friends = f }
    }

    /// Like optimista: cambia al momento y se deshace si falla.
    func toggleLike(_ item: FeedItem) async {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let liked = !items[i].likedByMe
        items[i].likedByMe = liked
        items[i].likeCount += liked ? 1 : -1
        do {
            if liked { try await api.like(item.id) } else { try await api.unlike(item.id) }
        } catch {
            if let j = items.firstIndex(where: { $0.id == item.id }) {
                items[j].likedByMe = !liked
                items[j].likeCount += liked ? -1 : 1
            }
        }
    }

    func commentCountChanged(_ itemId: String, by delta: Int) {
        guard let i = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[i].commentCount = max(0, items[i].commentCount + delta)
    }

    func markRead() async {
        guard unread > 0 else { return }
        unread = 0
        try? await api.markNotificationsRead()
        await refreshBadge()
    }

    /// Pide al servidor las novedades y las pone en la pestaña y en el icono de la app.
    func refreshBadge() async {
        guard let counts = try? await api.badgeCounts() else { return }
        apply(counts)
    }

    /// He abierto Amigos: lo de mis amigos deja de ser novedad.
    func markFeedSeen() async {
        guard let counts = try? await api.markFeedSeen() else { return }
        apply(counts)
    }

    private func apply(_ counts: BadgeCounts) {
        badgeTotal = counts.total
        UNUserNotificationCenter.current().setBadgeCount(counts.total) { _ in }
    }

    // MARK: Amistad

    func send(to person: Person) async -> FriendStatus? {
        let status = try? await api.sendFriendRequest(to: person.id)
        await refreshFriends()
        return status
    }

    func accept(_ userId: String) async {
        _ = try? await api.acceptFriend(userId)
        await refresh()
    }

    func remove(_ userId: String) async {
        try? await api.removeFriend(userId)
        await refresh()
    }

    func block(_ userId: String) async {
        try? await api.block(userId)
        await refresh()
    }
}
