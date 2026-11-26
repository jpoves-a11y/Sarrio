import SwiftUI
import UIKit

/// Sistema de diseño de Sarrio: claro, minimalista y con mucho aire, pero con profundidad.
/// - Un único color de acento (AccentColor en Assets) para acciones y datos destacados.
/// - Texto en negro/grises, fondos blancos y gris muy suave para separar bloques.
/// - Números grandes y en negrita con dígitos tabulares para las estadísticas.
/// - Profundidad: tarjetas que flotan con sombras suaves en capas, mapas 3D con relieve real
///   e interacción física (inclinación al tocar, muelles, háptica). Nada de adornos planos.
enum Theme {
    enum Colors {
        static let accent = Color.accentColor
        static let background = Color(uiColor: .systemBackground)
        static let groupedBackground = Color(red: 0.965, green: 0.965, blue: 0.97)
        /// Fondo de las pantallas: blanco limpio (los bloques no llevan caja, solo filos finos).
        static let page = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.08, green: 0.08, blue: 0.09)
        static let textSecondary = Color(red: 0.42, green: 0.43, blue: 0.45)
        static let separator = Color.black.opacity(0.07)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    /// Esquinas pequeñas y precisas (estilo editorial): nada de cápsulas ni tarjetas muy redondas.
    enum Radius {
        static let card: CGFloat = 8
        static let button: CGFloat = 8
        static let hero: CGFloat = 10
        /// Etiquetas, chips y botones pequeños.
        static let chip: CGFloat = 4
    }

    /// Sombras en capas: una cercana y nítida y otra lejana y difusa dan sensación de altura real.
    enum Elevation {
        case low, medium, high

        var layers: [(opacity: Double, radius: CGFloat, y: CGFloat)] {
            switch self {
            // Las tarjetas apenas se levantan; la profundidad de verdad queda para los mapas 3D
            case .low: [(0.03, 0.5, 0.5), (0.03, 4, 2)]
            case .medium: [(0.04, 1, 1), (0.05, 10, 5)]
            case .high: [(0.05, 2, 1), (0.12, 28, 16)]
            }
        }
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.72)
    }
}

extension View {
    /// Eleva la vista con sombras en capas (ver `Theme.Elevation`).
    func elevation(_ level: Theme.Elevation) -> some View {
        level.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: .black.opacity(layer.opacity), radius: layer.radius, x: 0, y: layer.y))
        }
    }
}

extension Font {
    /// Cifra grande de estadística (p. ej. "3.404").
    static let statValue = Font.sarrio(24, .semibold).monospacedDigit()
    static let statUnit = Font.sarrio(13, .medium)
    static let statLabel = Font.sarrio(12, .medium)
    static let screenTitle = Font.sarrio(30, .bold)
    /// Cifra protagonista (altitud de la cima más alta, total de cumbres…).
    static let heroValue = Font.sarrio(44, .semibold).monospacedDigit()
}
