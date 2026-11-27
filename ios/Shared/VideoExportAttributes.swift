#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity del vídeo de un replay mientras se prepara (pantalla de bloqueo e isla dinámica).
/// Se compila en la app (que la inicia, la actualiza y la termina) y en la extensión SarrioLive (que la dibuja).
struct VideoExportAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable {
        /// Cargando el mapa antes del primer fotograma
        case loading
        case rendering
        /// La app ha salido: el mapa no se puede dibujar en segundo plano
        case paused
        case done
        case failed
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// 0…1 del total
        var fraction: Double
        /// Segundos que faltan, cuando ya se sabe
        var remaining: Double?
    }

    /// «Aneto» o el título de la salida.
    var title: String
}

extension VideoExportAttributes.ContentState {
    var percentText: String { "\(Int((min(1, max(0, fraction)) * 100).rounded(.down))) %" }

    var statusText: String {
        switch phase {
        case .loading: "Cargando el mapa…"
        case .rendering:
            if let remaining, remaining > 0 {
                remaining < 60 ? "Quedan \(Int(remaining.rounded())) s" : "Quedan \(Int((remaining / 60).rounded(.up))) min"
            } else { "Preparando el vídeo…" }
        case .paused: "En pausa · abre Sarrio para seguir"
        case .done: "Vídeo listo"
        case .failed: "No se pudo crear el vídeo"
        }
    }
}
#endif
