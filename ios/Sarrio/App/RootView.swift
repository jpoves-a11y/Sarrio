import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isSignedIn {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { LibraryView() }
                .tabItem { Label("Cumbres", systemImage: "mountain.2.fill") }
            GlobeView()
                .tabItem { Label("Globo", systemImage: "globe.europe.africa.fill") }
            NavigationStack { FeedView() }
                .tabItem { Label("Amigos", systemImage: "person.2.fill") }
            NavigationStack { ChallengesView() }
                .tabItem { Label("Retos", systemImage: "flag.checkered") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
    }
}
