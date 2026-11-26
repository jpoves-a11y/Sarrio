import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                OnboardingView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.state)
    }
}

struct MainTabView: View {
    @Environment(AchievementsStore.self) private var achievements
    @Environment(DeepLinks.self) private var deepLinks

    var body: some View {
        @Bindable var achievements = achievements
        @Bindable var deepLinks = deepLinks
        TabView {
            NavigationStack { LibraryView() }
                .tabItem { Label("Cumbres", systemImage: "mountain.2.fill") }
            NavigationStack { GlobeView() }
                .tabItem { Label("Globo", systemImage: "globe.europe.africa.fill") }
            NavigationStack { FeedView() }
                .tabItem { Label("Amigos", systemImage: "person.2.fill") }
            NavigationStack { AchievementsView() }
                .tabItem { Label("Logros", systemImage: "medal") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
        // Emblemas nuevos de cualquier subida (importación, Apple Health, Polar): uno detrás de otro
        .sheet(item: $achievements.celebration, onDismiss: { achievements.next() }) { badge in
            BadgeCelebrationView(badge: badge)
        }
        // Invitación de un amigo (sarrio://u/<usuario>)
        .sheet(item: $deepLinks.profile) { link in
            NavigationStack { UserProfileView(username: link.username) }
        }
    }
}
