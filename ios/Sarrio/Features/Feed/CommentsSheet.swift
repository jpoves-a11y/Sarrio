import SwiftUI

/// Comentarios de un elemento del feed. Se borran manteniendo pulsado (los míos, o todos si es mío).
struct CommentsSheet: View {
    var item: FeedItem
    @Environment(\.apiClient) private var api
    @Environment(SocialStore.self) private var social
    @Environment(SessionStore.self) private var session
    @State private var comments: [FeedComment] = []
    @State private var loading = true
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if loading {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.l)
                        } else if comments.isEmpty {
                            Text("Sé el primero en comentar.")
                                .font(.sarrio(15))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Theme.Spacing.l)
                        }
                        ForEach(comments) { comment in
                            row(comment)
                                .contextMenu {
                                    if canDelete(comment) {
                                        Button(role: .destructive) { Task { await delete(comment) } } label: {
                                            Label("Borrar", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                }
                composer
            }
            .background(Theme.Colors.page)
            .navigationTitle("Comentarios")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private func row(_ c: FeedComment) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            AvatarView(name: c.author.displayName, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.author.displayName).font(.sarrio(14, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(c.createdAt.formatted(.relative(presentation: .named)))
                        .font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(c.body)
                    .font(.sarrio(15))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var composer: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField("", text: $text, prompt: Text("Escribe un comentario"), axis: .vertical)
                .font(.sarrio(15))
                .lineLimit(1...4)
                .focused($focused)
            Button {
                Task { await send() }
            } label: {
                if sending { ProgressView() } else {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
        .background(Theme.Colors.page)
    }

    private func canDelete(_ c: FeedComment) -> Bool {
        guard let me = session.me?.id else { return false }
        return c.author.id == me || item.actor.id == me
    }

    private func load() async {
        comments = (try? await api.comments(item.id)) ?? []
        loading = false
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        if let c = try? await api.addComment(item.id, body: body) {
            withAnimation(Theme.Motion.snappy) { comments.append(c) }
            text = ""
            social.commentCountChanged(item.id, by: 1)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func delete(_ c: FeedComment) async {
        if (try? await api.deleteComment(c.id)) != nil {
            withAnimation { comments.removeAll { $0.id == c.id } }
            social.commentCountChanged(item.id, by: -1)
        }
    }
}
