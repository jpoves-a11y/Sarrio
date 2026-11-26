import SwiftUI

/// Perfil de otra persona: sus cifras, sus cumbres en el globo y sus emblemas (si sois amigos),
/// con el botón de amistad y, en el menú, bloquear o denunciar.
struct UserProfileView: View {
    var username: String
    @Environment(\.apiClient) private var api
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var errorMessage: String?
    @State private var status: FriendStatus = .notFriends
    @State private var working = false
    @State private var selected: GlobeSelection?
    @State private var confirmBlock = false
    @State private var reporting = false
    @State private var reportSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let p = profile {
                    header(p)
                    if !p.ascents.isEmpty { globe(p) }
                    if !p.badges.isEmpty { badges(p) }
                    if p.ascents.isEmpty && status != .friends && status != .me {
                        Text("Cuando seáis amigos verás sus cimas y emblemas.")
                            .font(.sarrio(15))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let errorMessage {
                    EmptyStateView(icon: "person.crop.circle.badge.questionmark", title: "No disponible", message: errorMessage)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if profile != nil && status != .me {
                Menu {
                    Button { reporting = true } label: { Label("Denunciar", systemImage: "exclamationmark.bubble") }
                    Button(role: .destructive) { confirmBlock = true } label: { Label("Bloquear", systemImage: "hand.raised") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16))
                }
            }
        }
        .task { await load() }
        .confirmationDialog("¿Bloquear a \(profile?.displayName ?? "esta persona")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Bloquear", role: .destructive) {
                Task {
                    if let id = profile?.id { await social.block(id) }
                    dismiss()
                }
            }
        } message: {
            Text("Dejaréis de ser amigos y no os veréis en Sarrio.")
        }
        .confirmationDialog("¿Por qué lo denuncias?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(["Spam", "Contenido ofensivo", "Suplantación", "Otro motivo"], id: \.self) { reason in
                Button(reason) {
                    Task {
                        if let id = profile?.id { try? await api.report(targetType: "user", targetId: id, reason: reason) }
                        reportSent = true
                    }
                }
            }
        }
        .alert("Gracias, lo revisaremos", isPresented: $reportSent) { Button("OK", role: .cancel) {} }
    }

    private func header(_ p: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(name: p.displayName, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName)
                        .font(.sarrio(26, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("@\(p.username)").font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.sarrio(15)).foregroundStyle(Theme.Colors.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            StatRow(stats: [
                ("Cimas", "\(p.summary.uniquePeaks)", nil),
                ("Ascensiones", "\(p.summary.ascents)", nil),
                ("Más alta", p.summary.highestPeak?.ele?.groupedInteger ?? "—", p.summary.highestPeak?.ele == nil ? nil : "m"),
            ])
            friendButton
        }
    }

    @ViewBuilder private var friendButton: some View {
        switch status {
        case .notFriends:
            Button { act { await send() } } label: { buttonLabel("Añadir a amigos") }.buttonStyle(.primary)
        case .incoming:
            Button { act { await social.accept(profile!.id); status = .friends } } label: { buttonLabel("Aceptar solicitud") }.buttonStyle(.primary)
        case .outgoing:
            Button { act { await social.remove(profile!.id); status = .notFriends } } label: { buttonLabel("Solicitud enviada · Cancelar") }.buttonStyle(.secondary)
        case .friends:
            Menu {
                Button(role: .destructive) { act { await social.remove(profile!.id); status = .notFriends; await load() } } label: {
                    Label("Quitar de amigos", systemImage: "person.badge.minus")
                }
            } label: {
                Label("Amigos", systemImage: "checkmark").font(.sarrio(16, .semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.secondary)
        case .blocked, .me:
            EmptyView()
        }
    }

    private func buttonLabel(_ text: String) -> some View {
        Group { if working { ProgressView() } else { Text(text) } }
    }

    private func globe(_ p: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Sus cumbres")
            Globe3DMap(groups: p.peakGroups, selected: $selected, overviewToken: 0)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .elevation(.medium)
        }
    }

    private func badges(_ p: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Emblemas · \(p.badges.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(p.badges) { b in
                        VStack(spacing: 6) {
                            BadgeMedal(icon: b.icon, earned: true, size: 64, shine: b.tier == .legend)
                                .elevation(.medium)
                                .background { if b.tier == .legend { LegendAura(size: 64, onDark: false) } }
                                .frame(width: 72, height: 72)
                            Text(b.name)
                                .font(.sarrio(12, .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 84)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private func act(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func send() async {
        guard let p = profile else { return }
        let person = Person(id: p.id, username: p.username, displayName: p.displayName)
        status = await social.send(to: person) ?? status
    }

    private func load() async {
        do {
            let p = try await api.user(username: username)
            profile = p
            status = p.friendStatus
        } catch {
            errorMessage = "Esta persona no existe o no está disponible."
        }
    }
}
