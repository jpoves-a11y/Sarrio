import SwiftUI
import UIKit

@main
struct SarrioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let services = AppServices.shared

    init() {
        // Geist también en las barras del sistema (títulos, pestañas, controles segmentados)
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: UIFont.sarrio(32, .bold)]
        nav.titleTextAttributes = [.font: UIFont.sarrio(17, .semibold)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: UIFont.sarrio(17, .medium)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: UIFont.sarrio(10, .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.sarrio(13, .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.sarrio(13, .semibold)], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.session)
                .environment(services.library)
                .environment(services.achievements)
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
