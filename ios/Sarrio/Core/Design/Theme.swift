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
        // Claro y oscuro: cada color cambia con la apariencia (sigue al iPhone o a Ajustes → Apariencia).
        static let accent = Color.accentColor
        static let background = Color(uiColor: .systemBackground)
        static let groupedBackground = dynamic(light: (0.965, 0.965, 0.97), dark: (0.082, 0.086, 0.094))
        /// Fondo de las pantallas: blanco limpio en claro, casi negro en oscuro (sin caja, solo filos finos).
        static let page = dynamic(light: (1, 1, 1), dark: (0.055, 0.059, 0.063))
        /// Lo que flota (tarjetas sobre mapas, hojas): blanco en claro, gris muy oscuro en oscuro.
        static let surface = dynamic(light: (1, 1, 1), dark: (0.102, 0.106, 0.114))
        static let textPrimary = dynamic(light: (0.08, 0.08, 0.09), dark: (0.95, 0.95, 0.953))
        static let textSecondary = dynamic(light: (0.42, 0.43, 0.45), dark: (0.604, 0.616, 0.639))
        static let separator = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.07) })

        private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
            Color(uiColor: UIColor { trait in
                let c = trait.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }
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

/// Apariencia elegida en Ajustes: la del iPhone (por defecto), clara u oscura.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
