import SwiftUI

struct BadgesView: View {
    var body: some View {
        ContentUnavailableView("Emblemas", systemImage: "medal", description: Text("Gana emblemas por altura, número de cumbres, ascensiones invernales y más."))
            .navigationTitle("Emblemas")
    }
}
