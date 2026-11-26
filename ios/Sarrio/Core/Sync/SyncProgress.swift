import Foundation
import SarrioKit

/// Cómo va una sincronización (Apple Health o Polar), para enseñarla en vivo.
struct SyncProgress: Sendable, Equatable {
    enum Source: String, Sendable {
        case health, polar

        var title: String {
            switch self {
            case .health: "Apple Health"
            case .polar: "Polar"
            }
        }

        var icon: String {
            switch self {
            case .health: "heart.fill"
            case .polar: "dot.radiowaves.left.and.right"
            }
        }
    }

    enum Phase: Sendable, Equatable {
        /// Buscando entrenos nuevos.
        case searching
        /// Procesando uno a uno (leer la ruta, buscar cumbres y subirlo).
        case processing
        case done
    }

    var source: Source
    var phase: Phase = .searching
    /// Entrenos nuevos con GPS encontrados.
    var total = 0
    var processed = 0
    /// Cuántos de cada deporte (senderismo, carrera…).
    var bySport: [SportType: Int] = [:]
    var newSummits = 0
    var newActivities = 0
    /// Lo que se está procesando ahora («Senderismo · 14 jul»).
    var current: String?
    var startedAt = Date()
    /// Cuándo empezó a procesar (para estimar lo que queda).
    var processingStartedAt: Date?

    var fraction: Double { total == 0 ? 0 : Double(processed) / Double(total) }

    /// Segundos que quedan, según el ritmo hasta ahora (nil hasta tener una estimación fiable).
    var remaining: TimeInterval? {
        guard phase == .processing, processed >= 2, processed < total, let begin = processingStartedAt else { return nil }
        let perItem = Date().timeIntervalSince(begin) / Double(processed)
        return perItem * Double(total - processed)
    }

    /// Deportes ordenados de más a menos.
    var sportsSummary: [(sport: SportType, count: Int)] {
        bySport.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    mutating func begin(total: Int, sports: [SportType]) {
        self.total = total
        bySport = Dictionary(sports.map { ($0, 1) }, uniquingKeysWith: +)
        phase = total == 0 ? .done : .processing
        processingStartedAt = Date()
    }

    mutating func finishItem(_ outcome: ActivitySync.Outcome?) {
        processed += 1
        if let outcome, outcome.isNew {
            newActivities += 1
            newSummits += outcome.ascents.count
        }
    }
}

extension SportType {
    /// Deporte de Polar AccessLink (`HIKING`, `TRAIL_RUNNING`, `MOUNTAIN_BIKING`…).
    init(polarSport: String?) {
        let s = (polarSport ?? "").uppercased()
        if s.contains("TRAIL") { self = .trailRunning }
        else if s.contains("HIK") || s.contains("TREK") { self = .hiking }
        else if s.contains("MOUNTAINEER") || s.contains("ALPIN") { self = .mountaineering }
        else if s.contains("BACKCOUNTRY") || s.contains("SKI_TOUR") || s.contains("TOURING") { self = .backcountrySkiing }
        else if s.contains("SKI") || s.contains("SNOWBOARD") { self = .skiing }
        else if s.contains("SNOWSHOE") { self = .snowshoeing }
        else if s.contains("CLIMB") { self = .climbing }
        else if s.contains("RUN") { self = .running }
        else if s.contains("WALK") { self = .walking }
        else if s.contains("CYCL") || s.contains("BIK") { self = .cycling }
        else { self = .other }
    }
}
