import SwiftUI

/// Sistema de diseño de Sarrio: claro, minimalista y con mucho aire.
/// - Un único color de acento (AccentColor en Assets) para acciones y datos destacados.
/// - Texto en negro/grises, fondos blancos y gris muy suave para separar bloques.
/// - Números grandes y en negrita con dígitos tabulares para las estadísticas.
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
        static let card: CGFloat = 14
        static let button: CGFloat = 12
    }
}

extension Font {
    /// Cifra grande de estadística (p. ej. "3.404").
    static let statValue = Font.system(size: 24, weight: .bold).monospacedDigit()
    static let statUnit = Font.system(size: 13, weight: .semibold)
    static let statLabel = Font.system(size: 12, weight: .medium)
    static let screenTitle = Font.system(size: 30, weight: .heavy)
}
