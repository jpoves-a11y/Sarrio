import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var visibility: Visibility
    @State private var saving = false
    @State private var errorMessage: String?

    init(me: Me) {
        _displayName = State(initialValue: me.displayName)
        _username = State(initialValue: me.username)
        _bio = State(initialValue: me.bio ?? "")
        _visibility = State(initialValue: me.defaultVisibility)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $displayName)
                    .textContentType(.name)
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Theme.Colors.textSecondary)
                    TextField("usuario", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("\(bio.count)/280")
            }

            Section {
                Picker("Visibilidad por defecto", selection: $visibility) {
                    ForEach(Visibility.allCases) { v in
                        Label(v.title, systemImage: v.icon).tag(v)
                    }
                }
            } footer: {
                Text("Se aplica a tus nuevas ascensiones. Puedes cambiarla en cada una.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Editar perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else {
                    Button("Guardar") { Task { await save() } }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.update(ProfileUpdate(
                username: username,
                displayName: displayName,
                bio: bio,
                defaultVisibility: visibility
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
