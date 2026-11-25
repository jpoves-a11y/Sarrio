import SwiftUI

struct ChallengesView: View {
    var body: some View {
        ContentUnavailableView("Retos", systemImage: "flag.checkered", description: Text("Retos oficiales (tresmiles del Pirineo, techos de provincias…) y retos creados por tus amigos."))
            .navigationTitle("Retos")
    }
}
