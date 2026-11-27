import MapKit
import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var city: String
    @State private var visibility: Visibility
    @State private var saving = false
    @State private var errorMessage: String?

    // Foto
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropping: CropSource?
    @State private var localPhoto: UIImage?
    @State private var uploading = false
    @State private var showPicker = false

    // Sugerencias de ciudad
    @State private var cities = CitySuggestions()
    @FocusState private var cityFocused: Bool

    init(me: Me) {
        _displayName = State(initialValue: me.displayName)
        _username = State(initialValue: me.username)
        _bio = State(initialValue: me.bio ?? "")
        _city = State(initialValue: me.city ?? "")
        _visibility = State(initialValue: me.defaultVisibility)
    }

    var body: some View {
        Form {
            Section {
                photoHeader
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Nombre", text: $displayName)
                    .textContentType(.name)
                // El usuario se eligió al registrarse y no se cambia
                HStack {
                    Text("@\(username)").foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Usuario @\(username), no se puede cambiar")
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("\(bio.count)/280")
            }

            Section {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.Colors.accent)
                    TextField("Ciudad (opcional)", text: $city)
                        .textContentType(.addressCity)
                        .focused($cityFocused)
                        .onChange(of: city) { _, q in if cityFocused { cities.search(q) } }
                    if !city.isEmpty {
                        Button { city = ""; cities.clear() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if cityFocused {
                    ForEach(cities.results, id: \.self) { suggestion in
                        Button {
                            city = suggestion
                            cities.clear()
                            cityFocused = false
                        } label: {
                            Text(suggestion).font(.sarrio(15)).foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            } footer: {
                Text("Se verá en tu perfil junto a tu usuario.")
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
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropping = CropSource(image: image.normalizedOrientation())
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(item: $cropping) { source in
            AvatarCropView(image: source.image, onCancel: { cropping = nil }) { jpeg in
                cropping = nil
                localPhoto = UIImage(data: jpeg)
                Task { await upload(jpeg) }
            }
        }
    }

    // MARK: Foto

    private var photoHeader: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(name: displayName, userId: session.me?.id, avatarKey: session.me?.avatarKey, size: 96, image: localPhoto)
                    .overlay { if uploading { Circle().fill(.black.opacity(0.35)); ProgressView().tint(.white) } }
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.accent, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            Menu {
                Button { showPicker = true } label: { Label("Elegir foto", systemImage: "photo.on.rectangle") }
                if session.me?.avatarKey != nil || localPhoto != nil {
                    Button(role: .destructive) { Task { await removePhoto() } } label: { Label("Quitar foto", systemImage: "trash") }
                }
            } label: {
                Text(session.me?.avatarKey == nil && localPhoto == nil ? "Añadir foto" : "Cambiar foto")
                    .font(.sarrio(15, .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func upload(_ jpeg: Data) async {
        uploading = true
        defer { uploading = false }
        do {
            try await session.setAvatar(jpeg)
            errorMessage = nil
        } catch {
            localPhoto = nil
            errorMessage = error.localizedDescription
        }
    }

    private func removePhoto() async {
        uploading = true
        defer { uploading = false }
        do {
            try await session.setAvatar(nil)
            localPhoto = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Guardar

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.update(ProfileUpdate(
                displayName: displayName,
                bio: bio,
                city: city.trimmingCharacters(in: .whitespaces),
                defaultVisibility: visibility
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Sugerencias de ciudades mientras se escribe («Jaca, Huesca»), con MapKit.
@MainActor
@Observable
final class CitySuggestions: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [String] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        completer.queryFragment = q
    }

    func clear() {
        results = []
        completer.cancel()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Solo localidades: «Ciudad, Provincia» sin calle ni número
        let items = completer.results
            .filter { !$0.title.contains(where: \.isNumber) }
            .map { $0.subtitle.isEmpty ? $0.title : "\($0.title), \($0.subtitle.components(separatedBy: ",").first ?? "")" }
        let unique = Array(NSOrderedSet(array: items).compactMap { $0 as? String }.prefix(5))
        Task { @MainActor in self.results = unique }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

extension UIImage {
    /// La foto con la orientación aplicada a los píxeles (las del carrete suelen venir giradas).
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
