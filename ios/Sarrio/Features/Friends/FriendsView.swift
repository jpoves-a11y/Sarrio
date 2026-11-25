import SwiftUI

struct FriendsView: View {
    var body: some View {
        ScrollView {
            EmptyStateView(icon: "person.badge.plus", title: "Próximamente", message: "Busca a otros montañeros por su nombre de usuario.")
                .padding(.top, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Amigos")
    }
}
