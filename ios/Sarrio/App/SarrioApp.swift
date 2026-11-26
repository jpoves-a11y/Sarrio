import SwiftUI

@main
struct SarrioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.session)
                .environment(services.library)
                .environment(\.apiClient, services.api)
                .environment(\.peakPackStore, services.peakPackStore)
                .tint(Theme.Colors.accent)
                // Estética clara por decisión de diseño.
                .preferredColorScheme(.light)
                .task { await services.session.restore() }
                // GPX/FIT/TCX abiertos desde Archivos, Mail, AirDrop…
                .onOpenURL { url in
                    // sarrio://… son vueltas de inicio de sesión (Polar), no archivos
                    guard url.scheme != "sarrio" else { return }
                    Task { await services.library.importFile(at: url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, services.session.me != nil else { return }
                    Task {
                        await services.library.processSharedInbox()
                        await services.library.syncHealth()
                        await services.library.syncPolar()
                    }
                }
        }
    }
}
