import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section {
                Label(session.username ?? "—", systemImage: "person.crop.circle.fill")
            }
            Section {
                NavigationLink { BadgesView() } label: { Label("Emblemas", systemImage: "medal") }
                NavigationLink { FriendsView() } label: { Label("Amigos", systemImage: "person.2") }
                NavigationLink { SettingsView() } label: { Label("Ajustes", systemImage: "gearshape") }
                NavigationLink { CreditsView() } label: { Label("Créditos y licencias", systemImage: "info.circle") }
            }
            Section {
                Button("Cerrar sesión", role: .destructive) { session.signOut() }
            }
        }
        .navigationTitle("Perfil")
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Text("Datos de picos © OpenStreetMap contributors, disponibles bajo la Open Database License (ODbL).")
            Text("Mapas © Mapbox, © OpenStreetMap. Imágenes satélite © Maxar y otros proveedores de Mapbox.")
        }
        .navigationTitle("Créditos")
    }
}
