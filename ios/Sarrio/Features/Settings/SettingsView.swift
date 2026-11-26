import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if HealthKitService.isAvailable {
                    Toggle(isOn: Binding(
                        get: { library.healthConnected },
                        set: { on in
                            if on { Task { await library.connectHealth() } } else { library.disconnectHealth() }
                        }
                    )) {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                }
                SourceRow(icon: "doc", name: "Archivos GPX, FIT y TCX", status: "Disponible")
                SourceRow(icon: "dot.radiowaves.left.and.right", name: "Polar", status: "Próximamente")
                SourceRow(icon: "clock", name: "Garmin · Suunto · COROS", status: "En solicitud")
            } header: {
                Text("Fuentes de datos")
            } footer: {
                Text("Con Apple Health conectado, los entrenos nuevos con GPS se suben solos, también con la app cerrada. Puedes compartir archivos a Sarrio desde cualquier app.")
            }
            Section("Privacidad") {
                Label("Zonas privadas", systemImage: "eye.slash")
            }
            Section("Información") {
                NavigationLink { CreditsView() } label: { Label("Créditos y licencias", systemImage: "info.circle") }
            }
            Section {
                Button("Cerrar sesión") { session.signOut() }
                Button("Eliminar cuenta", role: .destructive) { confirmDelete = true }
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Ajustes")
        .confirmationDialog(
            "¿Eliminar tu cuenta?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar definitivamente", role: .destructive) {
                Task {
                    do { try await session.deleteAccount() } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("Se borrarán tu perfil, tus cumbres y tu actividad social. No se puede deshacer.")
        }
    }
}

private struct SourceRow: View {
    var icon: String
    var name: String
    var status: String

    var body: some View {
        HStack {
            Label(name, systemImage: icon)
            Spacer()
            Text(status).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Text("Datos de picos © OpenStreetMap contributors, disponibles bajo la Open Database License (ODbL).")
            Text("Mapas © Mapbox, © OpenStreetMap. Imágenes satélite de los proveedores de Mapbox.")
        }
        .navigationTitle("Créditos")
    }
}
