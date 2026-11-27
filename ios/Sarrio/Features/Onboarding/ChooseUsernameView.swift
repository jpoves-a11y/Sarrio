import SwiftUI

/// Elegir el nombre de usuario, una sola vez al registrarse: después ya no se puede cambiar.
/// Comprueba en vivo si está libre mientras se escribe.
struct ChooseUsernameView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.apiClient) private var api
    @State private var username: String = ""
    @State private var check: APIClient.UsernameAvailability?
    @State private var checking = false
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var normalized: String { username.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isAvailable: Bool { check?.username == normalized && check?.available == true }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer(minLength: Theme.Spacing.l)
            Image("SarrioMark")
                .resizable().scaledToFit()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Elige tu nombre de usuario")
                    .font(.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Así te encontrarán tus amigos. Piénsalo bien: no podrás cambiarlo después.")
                    .font(.sarrio(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 2) {
                    Text("@").font(.sarrio(24, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                    TextField("", text: $username, prompt: Text("usuario"))
                        .font(.sarrio(24, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { if isAvailable { Task { await confirm() } } }
                    if checking { ProgressView().controlSize(.small) }
                }
                Rectangle().fill(isAvailable ? Theme.Colors.accent : Theme.Colors.separator).frame(height: isAvailable ? 1.5 : 0.5)
                status
            }

            Text("De 3 a 20 caracteres: letras, números, punto o guion bajo.")
                .font(.sarrio(13))
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()
            if let errorMessage {
                Text(errorMessage).font(.sarrio(14)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await confirm() }
            } label: {
                if saving { ProgressView().tint(.white) } else { Text("Confirmar @\(normalized.isEmpty ? "usuario" : normalized)") }
            }
            .buttonStyle(.primary)
            .disabled(!isAvailable || saving)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Colors.page.ignoresSafeArea())
        .onAppear {
            username = session.me?.username ?? ""
            focused = true
        }
        .task(id: normalized) { await verify() }
    }

    @ViewBuilder private var status: some View {
        if let check, check.username == normalized, !normalized.isEmpty {
            if check.available {
                Label("Disponible", systemImage: "checkmark.circle.fill")
                    .font(.sarrio(14, .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            } else {
                Label(reasonText(check.reason), systemImage: "xmark.circle")
                    .font(.sarrio(14, .medium))
                    .foregroundStyle(.red)
            }
        } else {
            Text(" ").font(.sarrio(14))
        }
    }

    private func reasonText(_ reason: String?) -> String {
        switch reason {
        case "taken": "Ya lo tiene otra persona"
        case "reserved": "Ese nombre no está disponible"
        default: "No vale: revisa las reglas de abajo"
        }
    }

    private func verify() async {
        let q = normalized
        guard q.count >= 1 else { check = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        checking = true
        defer { checking = false }
        if let result = try? await api.usernameAvailability(q), !Task.isCancelled {
            check = result
        }
    }

    private func confirm() async {
        saving = true
        defer { saving = false }
        do {
            try await session.chooseUsername(normalized)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            await verify()
        }
    }
}
