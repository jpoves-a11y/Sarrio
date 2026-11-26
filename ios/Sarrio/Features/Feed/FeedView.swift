import SwiftUI

struct FeedView: View {
    var body: some View {
        ScrollView {
            EmptyStateView(icon: "person.2", title: "Próximamente", message: "Sigue a tus amigos para ver sus cumbres, emblemas y retos.")
                .padding(.top, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.page)
        .navigationTitle("Amigos")
    }
}
