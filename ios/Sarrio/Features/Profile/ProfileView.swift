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
                badgesStrip
                activitiesSection
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationRow(icon: "medal", title: "Emblemas") { BadgesView() }
                        Divider().padding(.leading, 52)
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

    /// Los tres últimos emblemas, en metal, con acceso a todos.
    @ViewBuilder private var badgesStrip: some View {
        let recent = Array(achievements.earned.prefix(3))
        if !recent.isEmpty {
            NavigationLink { BadgesView() } label: {
                HStack(spacing: Theme.Spacing.m) {
                    HStack(spacing: -14) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, badge in
                            BadgeMedal(icon: badge.icon, earned: true, size: 54)
                                .elevation(.medium)
                                .zIndex(Double(recent.count - index))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent[0].name)
                            .font(.sarrio(16, .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Último emblema")
                            .font(.sarrio(13))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
                }
                .padding(.vertical, Theme.Spacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableCard)
        }
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
                AvatarView(name: me.displayName, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.displayName)
                        .font(.sarrio(22, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("@\(me.username)")
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
