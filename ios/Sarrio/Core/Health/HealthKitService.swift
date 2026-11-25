import Foundation
import HealthKit

/// Acceso a entrenos y rutas de Apple Health. Implementación completa en la fase 3
/// (histórico, `HKObserverQuery` + entrega en segundo plano, lectura de `HKWorkoutRoute`).
final class HealthKitService: @unchecked Sendable {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        let types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        try await store.requestAuthorization(toShare: [], read: types)
    }
}
