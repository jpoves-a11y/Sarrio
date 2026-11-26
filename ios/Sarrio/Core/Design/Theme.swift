import SwiftUI

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

    enum Radius {
        static let card: CGFloat = 18
        static let button: CGFloat = 14
        static let hero: CGFloat = 26
    }

    /// Sombras en capas: una cercana y nítida y otra lejana y difusa dan sensación de altura real.
    enum Elevation {
        case low, medium, high

        var layers: [(opacity: Double, radius: CGFloat, y: CGFloat)] {
            switch self {
            case .low: [(0.04, 1, 1), (0.05, 8, 4)]
            case .medium: [(0.05, 2, 1), (0.08, 18, 10)]
            case .high: [(0.06, 3, 2), (0.14, 34, 20)]
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
    static let statValue = Font.system(size: 24, weight: .bold).monospacedDigit()
    static let statUnit = Font.system(size: 13, weight: .semibold)
    static let statLabel = Font.system(size: 12, weight: .medium)
    static let screenTitle = Font.system(size: 30, weight: .heavy)
    /// Cifra protagonista (altitud de la cima más alta, total de cumbres…).
    static let heroValue = Font.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit()
}
