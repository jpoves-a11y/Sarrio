import BackgroundTasks
import Foundation

/// Sincronización en segundo plano con BGTaskScheduler. Si iOS corta una sincronización de Polar
/// (al bloquear el iPhone, por ejemplo), se programa esta tarea y la app sigue después, en segundo
/// plano, con los entrenos que falten. La de Apple Health solo puede leer con el iPhone desbloqueado.
enum BackgroundSync {
    /// Tarea corta (unos 30 s), que iOS lanza con frecuencia.
    static var refreshIdentifier: String { (Bundle.main.bundleIdentifier ?? "com.sarrio") + ".refresh" }
    /// Tarea larga (varios minutos), cuando el iPhone está en reposo o cargando.
    static var processingIdentifier: String { (Bundle.main.bundleIdentifier ?? "com.sarrio") + ".sync" }

    /// Hay que llamarlo antes de que termine el arranque de la app.
    @MainActor
    static func register(run: @escaping @MainActor @Sendable () async -> Void) {
        for identifier in [refreshIdentifier, processingIdentifier] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                let ref = TaskRef(task)
                let work = Task { @MainActor in
                    await run()
                    ref.complete(success: true)
                }
                task.expirationHandler = {
                    work.cancel()
                    ref.complete(success: false)
                }
            }
        }
    }

    static func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(processing)
    }
}

/// La tarea de iOS, para completarla una sola vez desde el trabajo o desde su caducidad.
private final class TaskRef: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var done = false

    init(_ task: BGTask) { self.task = task }

    func complete(success: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
    }
}
