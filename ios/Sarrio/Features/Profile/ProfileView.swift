import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AchievementsStore.self) private var achievements
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if let me = session.me {
                    header(me)
                    Card(elevation: .medium) {
                        StatRow(stats: [
                            ("Cumbres", "\(library.library?.summary.uniquePeaks ?? 0)", nil),
                            ("Desnivel", library.totalElevationGain.groupedInteger, "m"),
                            ("Emblemas", "\(achievements.catalog?.earned ?? 0)", nil),
                        ])
                    }
                }
                badgesShowcase
                YearStrip()
                activitiesSection
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationRow(icon: "person.2", title: "Amigos") { FriendsView() }
                        Divider().padding(.leading, 52)
                        NavigationRow(icon: "gearshape", title: "Ajustes") { SettingsView() }
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Perfil")
        .task { if library.library == nil { await library.load() } }
        .task { await achievements.loadBadges() }
        .toolbar {
            Button("Editar") { editing = true }
        }
        .sheet(isPresented: $editing) {
            if let me = session.me { NavigationStack { EditProfileView(me: me) } }
        }
    }

    /// Vitrina de emblemas: el recuento grande, una barra fina y los mejores en grande (primero las
    /// Leyendas con su aura). Sin ninguno aún, los más cercanos en gris. Toda la vitrina abre Emblemas.
    private var badgesShowcase: some View {
        let catalog = achievements.catalog
        let tierRank: [BadgeTier: Int] = [.legend: 0, .special: 1, .gold: 2, .silver: 3, .bronze: 4]
        let best = achievements.earned.sorted {
            let a = tierRank[$0.tier] ?? 9, b = tierRank[$1.tier] ?? 9
            return a != b ? a < b : ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast)
        }
        let shown = best.isEmpty ? Array(achievements.closest.prefix(3)) : Array(best.prefix(8))
        return NavigationLink { BadgesView() } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("EMBLEMAS")
                        .font(.sarrio(12, .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if let catalog {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(catalog.earned)").font(.sarrio(26, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                            Text("de \(catalog.total)").font(.sarrio(14, .medium)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
                }
                if let catalog {
                    ProgressBar(fraction: Double(catalog.earned) / Double(max(catalog.total, 1)), height: 2)
                }
                if shown.isEmpty {
                    Text("Sube tu primera cima y conseguirás tu primer emblema.")
                        .font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    if best.isEmpty {
                        Text("Te falta poco").font(.sarrio(14, .medium)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Theme.Spacing.l) {
                            ForEach(shown) { badge in
                                VStack(spacing: 6) {
                                    BadgeMedal(icon: badge.icon, earned: badge.isEarned || badge.tier == .legend,
                                               progress: badge.isEarned ? nil : badge.progress?.fraction, size: 76, shine: badge.tier == .legend)
                                        .opacity(badge.isEarned || badge.tier != .legend ? 1 : 0.55)
                                        .elevation(badge.isEarned ? .medium : .low)
                                        .background { if badge.tier == .legend && badge.isEarned { LegendAura(size: 76, onDark: false) } }
                                        .frame(width: 92, height: 92)
                                    Text(badge.name)
                                        .font(.sarrio(12, .semibold))
                                        .foregroundStyle(badge.isEarned ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(width: 92)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.vertical, Theme.Spacing.m)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
        }
        .buttonStyle(.pressableCard)
    }

    /// Últimas salidas de montaña (con o sin cimas) y acceso a todas.
    private var activitiesSection: some View {
        let mountain = library.activities.filter { $0.sport.isMountain }
        return VStack(spacing: Theme.Spacing.s) {
            HStack {
                SectionHeader(title: "Actividades de montaña")
                NavigationLink { MountainActivitiesView() } label: {
                    Text(mountain.isEmpty ? "Ver" : "Ver todas")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.top, Theme.Spacing.s)
            if mountain.isEmpty {
                Card(elevation: .low) {
                    HStack(spacing: Theme.Spacing.m) {
                        SportBadge(sport: .hiking, size: 40)
                        Text("Tus salidas de senderismo y trail de Apple Watch, Polar o tus archivos aparecerán aquí, con o sin cimas.")
                            .font(.sarrio(14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            } else {
                ForEach(Array(mountain.prefix(3).enumerated()), id: \.element.id) { index, activity in
                    NavigationLink { ActivityDetailView(activity: activity) } label: { MountainActivityRow(activity: activity) }
                        .buttonStyle(.pressableCard)
                        .staggeredAppear(index + 1)
                }
            }
        }
    }

    private func header(_ me: Me) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(name: me.displayName, userId: me.id, avatarKey: me.avatarKey, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.displayName)
                        .font(.sarrio(22, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(me.city.map { "@\(me.username) · \($0)" } ?? "@\(me.username)")
                        .font(.sarrio(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let bio = me.bio, !bio.isEmpty {
                Text(bio)
                    .font(.sarrio(15))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
}

/// Fila de navegación limpia: icono, título y chevron.
struct NavigationRow<Destination: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 22)
                Text(title).font(.sarrio(16)).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
