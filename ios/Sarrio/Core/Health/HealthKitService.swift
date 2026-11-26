import CoreLocation
import Foundation
import HealthKit
import SarrioKit

/// Entreno de Apple Health ya convertido a tipos propios (los objetos de HealthKit no salen de aquí).
struct HealthWorkout: Sendable {
    var uuid: UUID
    var sport: SportType
    var start: Date
    var end: Date
    var distance: Double?
    var elevationGain: Double?
    var points: [TrackPoint]
}

/// Acceso a entrenos y rutas de Apple Health.
///
/// - Histórico y novedades con `HKAnchoredObjectQuery`: el ancla se guarda, así que cada consulta
///   devuelve solo los entrenos nuevos desde la anterior (la primera, todo el histórico).
/// - `HKObserverQuery` + entrega en segundo plano: iOS despierta la app cuando se guarda un entreno.
final class HealthKitService: @unchecked Sendable {
    private let store = HKHealthStore()
    private let defaults: UserDefaults
    private static let anchorKey = "healthkit.workoutAnchor"
    private static let connectedKey = "healthkit.connected"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit no deja leer mientras el iPhone está bloqueado (los datos de Salud van cifrados):
    /// «Protected health data is inaccessible». No es un fallo: se reintenta al desbloquear.
    static func isLockedError(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible
    }

    /// Si el usuario ha conectado Apple Health desde Sarrio. HealthKit no dice si se concedió la lectura.
    var isConnected: Bool { defaults.bool(forKey: Self.connectedKey) }

    private var readTypes: Set<HKObjectType> { [HKObjectType.workoutType(), HKSeriesType.workoutRoute()] }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
        defaults.set(true, forKey: Self.connectedKey)
    }

    func disconnect() {
        defaults.set(false, forKey: Self.connectedKey)
        defaults.removeObject(forKey: Self.anchorKey)
        Task { try? await store.disableAllBackgroundDelivery() }
    }

    // MARK: - Entrenos nuevos

    /// Deportes al aire libre en los que puede haber cumbres.
    private static let outdoorTypes: [HKWorkoutActivityType] = [
        .hiking, .walking, .running, .cycling, .climbing, .crossCountrySkiing, .downhillSkiing,
        .snowSports, .snowboarding, .mixedCardio,
    ]

    private var workoutPredicate: NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: Self.outdoorTypes.map { HKQuery.predicateForWorkouts(with: $0) })
    }

    /// Resultado de una consulta: los entrenos y el ancla que hay que guardar si se procesan bien.
    struct Batch: Sendable {
        var workouts: [HealthWorkout]
        /// Quedan más entrenos por leer (el histórico se lee por lotes).
        var hasMore: Bool
        fileprivate var anchor: Data?
    }

    /// Entrenos añadidos desde el último `commit` (la primera vez, todo el histórico), con su ruta.
    /// Si la subida falla y no se llama a `commit`, los mismos entrenos volverán a salir.
    func newWorkouts(limit: Int = 20) async throws -> Batch {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(workoutPredicate)],
            anchor: loadAnchor(),
            limit: limit
        )
        let result = try await descriptor.result(for: store)
        var workouts: [HealthWorkout] = []
        for workout in result.addedSamples {
            let points = try await routePoints(for: workout)
            guard points.count >= 2 else { continue } // sin GPS no hay cumbres que detectar
            workouts.append(HealthWorkout(
                uuid: workout.uuid,
                sport: Self.sport(for: workout.workoutActivityType),
                start: workout.startDate,
                end: workout.endDate,
                distance: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                    ?? workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter()),
                elevationGain: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
                points: points
            ))
        }
        let anchor = try? NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true)
        return Batch(
            workouts: workouts.sorted { $0.start < $1.start },
            hasMore: result.addedSamples.count == limit,
            anchor: anchor
        )
    }

    func commit(_ batch: Batch) {
        if let anchor = batch.anchor { defaults.set(anchor, forKey: Self.anchorKey) }
    }

    private func routePoints(for workout: HKWorkout) async throws -> [TrackPoint] {
        let routes = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)

        var points: [TrackPoint] = []
        for case let route as HKWorkoutRoute in routes {
            points += try await locations(of: route).map {
                TrackPoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    elevation: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                    time: $0.timestamp
                )
            }
        }
        return points
    }

    private func locations(of route: HKWorkoutRoute) async throws -> [CLLocation] {
        let buffer = LocationBuffer()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    buffer.finish { _ in continuation.resume(throwing: error) }
                    return
                }
                buffer.append(locations ?? [])
                if done { buffer.finish { continuation.resume(returning: $0) } }
            }
            store.execute(query)
        }
    }

    // MARK: - Segundo plano

    /// Registra el observador. Hay que llamarlo en cada arranque (también cuando iOS despierta la app).
    func startObserving(onChange: @escaping @Sendable () async -> Void) {
        guard Self.isAvailable, isConnected else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            // Hay que avisar a HealthKit al terminar; si no, deja de despertar la app.
            let done = UncheckedSendable(completion)
            Task {
                await onChange()
                done.value()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, _ in }
    }

    // MARK: - Ancla

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func sport(for type: HKWorkoutActivityType) -> SportType {
        switch type {
        case .hiking: .hiking
        case .walking: .walking
        case .running: .running
        case .cycling: .cycling
        case .climbing: .climbing
        case .crossCountrySkiing: .backcountrySkiing
        case .downhillSkiing, .snowboarding, .snowSports: .skiing
        default: .other
        }
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Acumula localizaciones que llegan por lotes desde HealthKit (en su propia cola).
private final class LocationBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [CLLocation] = []
    private var finished = false

    func append(_ more: [CLLocation]) {
        lock.lock(); defer { lock.unlock() }
        locations += more
    }

    /// Llama a `body` una sola vez, aunque HealthKit avise varias veces.
    func finish(_ body: ([CLLocation]) -> Void) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let result = locations
        lock.unlock()
        body(result)
    }
}
