import SwiftUI

struct FeedView: View {
    var body: some View {
        ContentUnavailableView("Amigos", systemImage: "person.2", description: Text("Aquí verás las cumbres, emblemas y retos de tus amigos, con likes y comentarios."))
            .navigationTitle("Amigos")
    }
}
