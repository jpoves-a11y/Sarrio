import SwiftUI
import UIKit

/// Servicios compartidos de la app. Se crean una sola vez, también cuando iOS despierta la app
/// en segundo plano para entregar un entreno nuevo de Apple Health.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let api: APIClient
    let peakPackStore: PeakPackStore
    let healthKit: HealthKitService
    let sync: ActivitySync
    let session: SessionStore
    let library: LibraryStore

    private init() {
        let api = APIClient(baseURL: AppConfig.apiBaseURL)
        let peakPackStore = PeakPackStore(api: api)
        let healthKit = HealthKitService()
        let sync = ActivitySync(api: api, peakPackStore: peakPackStore, healthKit: healthKit)
        self.api = api
        self.peakPackStore = peakPackStore
        self.healthKit = healthKit
        self.sync = sync
        self.session = SessionStore(api: api)
        self.library = LibraryStore(api: api, sync: sync)
    }

    /// Observa Apple Health y sube los entrenos nuevos aunque la app esté cerrada.
    func startHealthObserver() {
        let sync = self.sync
        healthKit.startObserving {
            guard KeychainStore.sessionToken != nil else { return }
            _ = try? await sync.syncHealth()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Debe registrarse en cada arranque para que la entrega en segundo plano funcione.
        AppServices.shared.startHealthObserver()
        return true
    }
}
