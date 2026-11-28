import Observation
import SwiftUI
import UIKit
import UserNotifications

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
    let achievements: AchievementsStore
    let social: SocialStore
    let deepLinks = DeepLinks()

    private init() {
        MapPrefetcher.configureCache()
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
        self.achievements = AchievementsStore(api: api)
        self.social = SocialStore(api: api)
        // Al desbloquear el iPhone, la sincronización con Salud que quedó pendiente
        let library = self.library
        unlockTask = Task {
            for await _ in NotificationCenter.default.notifications(named: UIApplication.protectedDataDidBecomeAvailableNotification) {
                if library.pendingHealthSync, KeychainStore.sessionToken != nil { await library.syncHealth() }
            }
        }
    }

    private var unlockTask: Task<Void, Never>?

    /// Observa Apple Health y sube los entrenos nuevos aunque la app esté cerrada.
    func startHealthObserver() {
        let sync = self.sync
        healthKit.startObserving {
            guard KeychainStore.sessionToken != nil else { return }
            _ = try? await sync.syncHealth()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Debe registrarse en cada arranque para que la entrega en segundo plano funcione.
        AppServices.shared.startHealthObserver()
        // Sincronizaciones que iOS cortó (iPhone bloqueado): siguen en segundo plano
        BackgroundSync.register {
            let services = AppServices.shared
            guard KeychainStore.sessionToken != nil else { return }
            await services.library.refreshProviders()
            await services.library.syncPolar()
            await services.library.syncHealth()
        }
        return true
    }

    // MARK: Notificaciones push

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await Push.register(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push: no se pudo registrar", error)
    }

    // Con completionHandler y no `async`: el puente que genera Swift para la versión async llama al
    // completionHandler de UIKit desde un hilo cualquiera, y UIKit exige el principal (al abrir la app
    // tocando una notificación con la app cerrada, se cerraba: NSAssert en
    // _performBlockAfterCATransactionCommitSynchronizes).

    /// Con la app abierta: se enseña igual (banner y sonido) y se actualiza Amigos.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Task { await AppServices.shared.social.refresh() }
                completionHandler([.banner, .list, .sound, .badge])
            }
        }
    }

    /// Al tocarla: a Amigos (o a las solicitudes).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let open = response.notification.request.content.userInfo["open"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AppServices.shared.deepLinks.tab = .friends
                if open == "friends" { AppServices.shared.deepLinks.showFriends = true }
                completionHandler()
            }
        }
    }
}

/// Notificaciones push: permiso (una vez, tras iniciar sesión) y registro del token en el servidor.
@MainActor
enum Push {
    /// Pide permiso si aún no se ha decidido, y registra el iPhone si está concedido.
    static func setUp() async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func register(token: String) async {
        guard KeychainStore.sessionToken != nil else { return }
        let raw = Bundle.main.object(forInfoDictionaryKey: "SarrioAPSEnvironment") as? String ?? "production"
        try? await AppServices.shared.api.registerDevice(token: token, environment: raw == "development" ? "sandbox" : "production")
    }
}

/// Perfil a abrir desde un enlace `sarrio://u/<usuario>`.
struct ProfileLink: Identifiable, Hashable {
    var username: String
    var id: String { username }
}

/// Enlaces que abren pantallas desde fuera (invitaciones de amigos).
@MainActor
@Observable
final class DeepLinks {
    var profile: ProfileLink?
    /// Pestaña elegida (las notificaciones llevan a Amigos).
    var tab: AppTab = .summits
    /// Abrir la pantalla de amigos (al tocar una solicitud).
    var showFriends = false
}

enum AppTab: Hashable { case summits, globe, friends, achievements, profile }
