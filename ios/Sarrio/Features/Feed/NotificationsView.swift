import SwiftUI

/// Avisos: solicitudes (con aceptar en la misma fila), likes y comentarios.
struct NotificationsView: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if social.notifications.isEmpty {
                    EmptyStateView(icon: "bell", title: "Sin avisos", message: "Aquí verás las solicitudes de amistad, los me gusta y los comentarios.")
                        .padding(.top, Theme.Spacing.l)
                }
                ForEach(social.notifications) { n in row(n) }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Avisos")
        .task { await social.markRead() }
        .refreshable { await social.refresh() }
    }

    private func row(_ n: AppNotification) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            AvatarView(name: n.actor?.displayName ?? "Sarrio", userId: n.actor?.id, avatarKey: n.actor?.avatarKey, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                (Text(n.actor?.displayName ?? "Sarrio").font(.sarrio(15, .semibold)) + Text(" " + n.text).font(.sarrio(15)))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(n.createdAt.formatted(.relative(presentation: .named)))
                    .font(.sarrio(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            if n.kind == .friendRequest, let actor = n.actor, social.friends?.incoming.contains(where: { $0.id == actor.id }) == true {
                Button("Aceptar") { Task { await social.accept(actor.id) } }
                    .font(.sarrio(14, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .buttonStyle(.plain)
            } else if !n.read {
                Rectangle().fill(Theme.Colors.accent).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }
}
