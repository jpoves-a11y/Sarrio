import SwiftUI

struct FriendsView: View {
    var body: some View {
        ContentUnavailableView("Buscar amigos", systemImage: "person.badge.plus", description: Text("Busca usuarios por nombre y envía solicitudes de amistad."))
            .navigationTitle("Buscar amigos")
    }
}
