import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if let me = session.me {
                    header(me)
                    Card {
                        // Fase 3-5: valores reales desde ascensiones y emblemas.
                        StatRow(stats: [
                            ("Cumbres", "0", nil),
                            ("Desnivel", "0", "m"),
                            ("Emblemas", "0", nil),
                        ])
                    }
                }
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
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Perfil")
        .toolbar {
            Button("Editar") { editing = true }
        }
        .sheet(isPresented: $editing) {
            if let me = session.me { NavigationStack { EditProfileView(me: me) } }
        }
    }

    private func header(_ me: Me) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(name: me.displayName, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("@\(me.username)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let bio = me.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 15))
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
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.Colors.textPrimary)
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
