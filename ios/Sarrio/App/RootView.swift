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
    @Environment(SocialStore.self) private var social

    var body: some View {
        @Bindable var achievements = achievements
        @Bindable var deepLinks = deepLinks
        TabView(selection: $deepLinks.tab) {
            NavigationStack { LibraryView() }
                .tabItem { Label("Cumbres", systemImage: "mountain.2.fill") }
                .tag(AppTab.summits)
            NavigationStack { GlobeView() }
                .tabItem { Label("Globo", systemImage: "globe.europe.africa.fill") }
                .tag(AppTab.globe)
            NavigationStack { FeedView() }
                .tabItem { Label("Amigos", systemImage: "person.2.fill") }
                .tag(AppTab.friends)
                // Novedades: avisos sin leer y lo nuevo de mis amigos
                .badge(social.badgeTotal)
            NavigationStack { AchievementsView() }
                .tabItem { Label("Logros", systemImage: "medal") }
                .tag(AppTab.achievements)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .task {
            // Permiso de notificaciones (una vez) y las novedades al entrar
            await Push.setUp()
            await social.refreshBadge()
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
