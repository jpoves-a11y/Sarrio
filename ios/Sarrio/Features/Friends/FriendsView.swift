import SwiftUI

/// Amigos: buscar personas, solicitudes recibidas y enviadas, tus amigos e invitar con un enlace.
struct FriendsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(SessionStore.self) private var session
    @Environment(\.apiClient) private var api
    @State private var query = ""
    @State private var results: [Person] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                searchField
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    section("Resultados") {
                        if results.isEmpty && !searching {
                            Text(query.count < 2 ? "Escribe al menos dos letras" : "Nadie con ese nombre")
                                .font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary).padding(.vertical, Theme.Spacing.s)
                        }
                        ForEach(results) { person in PersonRow(person: person, status: person.friendStatus ?? .notFriends) }
                    }
                } else {
                    if let incoming = social.friends?.incoming, !incoming.isEmpty {
                        section("Solicitudes") {
                            ForEach(incoming) { person in PersonRow(person: person, status: .incoming) }
                        }
                    }
                    section("Tus amigos") {
                        if social.friends?.friends.isEmpty ?? true {
                            Text("Busca a tus compañeros de cordada o mándales tu enlace.")
                                .font(.sarrio(14)).foregroundStyle(Theme.Colors.textSecondary).padding(.vertical, Theme.Spacing.s)
                        }
                        ForEach(social.friends?.friends ?? []) { person in PersonRow(person: person, status: .friends) }
                    }
                    if let outgoing = social.friends?.outgoing, !outgoing.isEmpty {
                        section("Enviadas") {
                            ForEach(outgoing) { person in PersonRow(person: person, status: .outgoing) }
                        }
                    }
                    if let me = session.me, let link = URL(string: "sarrio://u/\(me.username)") {
                        ShareLink(item: link, subject: Text("Sarrio"),
                                  message: Text("Añádeme en Sarrio para ver nuestras cimas: @\(me.username)")) {
                            Label("Invitar con tu enlace", systemImage: "square.and.arrow.up")
                                .font(.sarrio(16, .semibold))
                        }
                        .buttonStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Amigos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await social.refreshFriends() }
        .task(id: query) { await search() }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary)
            TextField("", text: $query, prompt: Text("Buscar por nombre o usuario"))
                .font(.sarrio(16, .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if searching { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title)
            content()
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        searching = true
        let found = (try? await api.searchUsers(q)) ?? []
        guard !Task.isCancelled else { return }
        searching = false
        results = found
    }
}

/// Persona con su botón según la relación (añadir, aceptar, pendiente, amigos).
struct PersonRow: View {
    var person: Person
    @State var status: FriendStatus
    @Environment(SocialStore.self) private var social
    @State private var working = false

    var body: some View {
        NavigationLink { UserProfileView(username: person.username) } label: {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(name: person.displayName, userId: person.id, avatarKey: person.avatarKey, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayName)
                        .font(.sarrio(16, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(person.city.map { "@\(person.username) · \($0)" } ?? "@\(person.username)")
                        .font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                action
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    @ViewBuilder private var action: some View {
        switch status {
        case .notFriends:
            pill("Añadir", filled: true) { status = await social.send(to: person) ?? status }
        case .incoming:
            pill("Aceptar", filled: true) { await social.accept(person.id); status = .friends }
        case .outgoing:
            pill("Pendiente", filled: false) { await social.remove(person.id); status = .notFriends }
        case .friends, .blocked, .me:
            EmptyView()
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            working = true
            Task {
                await action()
                working = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            Group { if working { ProgressView().controlSize(.small) } else { Text(title) } }
                .font(.sarrio(14, .semibold))
                .foregroundStyle(filled ? .white : Theme.Colors.textSecondary)
                .frame(minWidth: 84, minHeight: 32)
                .background(filled ? Theme.Colors.accent : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(filled ? .clear : Theme.Colors.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}
