import SwiftUI

struct BadgesView: View {
    var body: some View {
        ScrollView {
            EmptyStateView(icon: "medal", title: "Próximamente", message: "Gana emblemas por altura, número de cumbres, invernales y más.")
                .padding(.top, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.page)
        .navigationTitle("Emblemas")
    }
}
