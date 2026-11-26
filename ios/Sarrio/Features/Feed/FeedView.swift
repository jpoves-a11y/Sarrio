import SwiftUI

/// Pestaña Amigos: lo que hacéis tú y tus amigos (salidas, cimas, emblemas y retos), con likes
/// y comentarios. Arriba, los avisos y añadir amigos.
struct FeedView: View {
    @Environment(SocialStore.self) private var social
    @State private var showNotifications = false
    @State private var showFriends = false
    @State private var commentsFor: FeedItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if social.items.isEmpty {
                    if !social.loadedOnce {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                    } else if let error = social.errorMessage {
                        EmptyStateView(icon: "person.2", title: "No se ha podido cargar", message: error, actionTitle: "Reintentar") {
                            Task { await social.refresh() }
                        }
                    } else {
                        EmptyStateView(icon: "person.2", title: "Tu cordada",
                                       message: "Añade amigos para ver sus cimas, emblemas y retos.",
                                       actionTitle: "Añadir amigos") { showFriends = true }
                    }
                } else {
                    if social.friends?.incoming.isEmpty == false { requestsBanner }
                    ForEach(Array(social.items.enumerated()), id: \.element.id) { index, item in
                        FeedCard(item: item) { commentsFor = item }
                            .staggeredAppear(min(index, 6))
                            .onAppear { if item.id == social.items.last?.id { Task { await social.loadMore() } } }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Amigos")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showFriends = true } label: {
                    Image(systemName: "person.badge.plus").font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel("Añadir amigos")
                Button { showNotifications = true } label: {
                    Image(systemName: "bell").font(.system(size: 16, weight: .regular))
                        .overlay(alignment: .topTrailing) {
                            if social.unread > 0 {
                                Text("\(min(social.unread, 9))")
                                    .font(.sarrio(10, .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    .offset(x: 8, y: -7)
                            }
                        }
                }
                .accessibilityLabel(social.unread > 0 ? "Avisos, \(social.unread) sin leer" : "Avisos")
            }
        }
        .task { await social.refresh() }
        .refreshable { await social.refresh() }
        .navigationDestination(isPresented: $showNotifications) { NotificationsView() }
        .navigationDestination(isPresented: $showFriends) { FriendsView() }
        .sheet(item: $commentsFor) { item in
            CommentsSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Solicitudes pendientes, discretas arriba del todo.
    private var requestsBanner: some View {
        let count = social.friends?.incoming.count ?? 0
        return Button { showFriends = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                Text(count == 1 ? "1 solicitud de amistad" : "\(count) solicitudes de amistad")
                    .font(.sarrio(15, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }
}

/// Un elemento del feed: quién, qué y cuándo; likes y comentarios abajo.
struct FeedCard: View {
    var item: FeedItem
    var onComments: () -> Void
    @Environment(SocialStore.self) private var social
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            content
            actions
        }
        .padding(.vertical, Theme.Spacing.m)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    private var isMine: Bool { item.actor.id == session.me?.id }

    private var header: some View {
        NavigationLink {
            UserProfileView(username: item.actor.username)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                AvatarView(name: item.actor.displayName, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMine ? "Tú" : item.actor.displayName)
                        .font(.sarrio(15, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.at.formatted(.relative(presentation: .named)))
                        .font(.sarrio(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMine)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .activity, .ascent:
            outing
        case .badge:
            if let badge = item.badge {
                achievement(icon: badge.icon, legend: badge.tier == .legend, verb: "ha conseguido", title: badge.name, subtitle: badge.description)
            }
        case .challengeCompleted:
            if let challenge = item.challenge {
                achievement(icon: challenge.medalIcon, legend: challenge.badgeId != nil, verb: "ha completado", title: challenge.title, subtitle: nil)
            }
        case .unknown:
            EmptyView()
        }
    }

    /// Salida o cima: las cimas con su altitud y las cifras de la actividad. Abre el detalle.
    @ViewBuilder private var outing: some View {
        let peaks = item.ascents ?? []
        let card = VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if peaks.isEmpty, let activity = item.activity {
                HStack(spacing: Theme.Spacing.s) {
                    SportBadge(sport: activity.sport, size: 30)
                    Text(activity.displayTitle)
                        .font(.sarrio(20, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(peaks) { ascent in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(ascent.peak.displayName)
                        .font(.sarrio(20, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.s)
                    if let ele = ascent.peak.ele {
                        Text("\(ele.groupedInteger) m")
                            .font(.sarrio(17, .semibold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            if let activity = item.activity { stats(activity) }
        }
        .contentShape(Rectangle())
        if let activity = item.activity {
            NavigationLink { ActivityDetailView(activity: activity) } label: { card }
                .buttonStyle(.pressableCard)
        } else {
            card
        }
    }

    private func stats(_ a: Activity) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            if let d = a.distanceM, d > 0 { stat((d / 1000).formatted(.number.precision(.fractionLength(1))), "km") }
            if let g = a.elevGainM, g > 0 { stat(g.groupedInteger, "m D+") }
            if let s = a.durationS, s > 0 {
                let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
                stat(h > 0 ? "\(h) h \(m)" : "\(m)", h > 0 ? "min" : "min")
            }
        }
        .padding(.top, 2)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.sarrio(15, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(unit).font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func achievement(icon: String, legend: Bool, verb: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            BadgeMedal(icon: icon, earned: true, size: 64, shine: legend)
                .elevation(.medium)
                .background { if legend { LegendAura(size: 64, onDark: false) } }
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(verb.uppercased())
                    .font(.sarrio(11, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(legend ? LegendColors.gold : Theme.Colors.textSecondary)
                Text(title)
                    .font(.sarrio(19, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.sarrio(13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.l) {
            Button {
                Task { await social.toggleLike(item) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: item.likedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(item.likedByMe ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .scaleEffect(item.likedByMe ? 1.12 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: item.likedByMe)
                    if item.likeCount > 0 {
                        Text("\(item.likeCount)").font(.sarrio(14, .medium).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: item.likedByMe)
            .accessibilityLabel(item.likedByMe ? "Quitar me gusta" : "Me gusta")

            Button(action: onComments) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if item.commentCount > 0 {
                        Text("\(item.commentCount)").font(.sarrio(14, .medium).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comentarios")
            Spacer()
        }
    }
}
