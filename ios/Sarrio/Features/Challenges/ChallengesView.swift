import SwiftUI

struct ChallengesView: View {
    var body: some View {
        ScrollView {
            EmptyStateView(icon: "flag.checkered", title: "Próximamente", message: "Tresmiles del Pirineo, techos de provincias y retos con tus amigos.")
                .padding(.top, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Retos")
    }
}
