import SwiftUI
import UIKit

/// Tipografía de Sarrio: Geist (sans geométrica sobria, licencia OFL), con cifras tabulares.
/// Pesos contenidos: nada por encima de Bold. Usa siempre `.sarrio(_:_:)` en lugar de `.system`.
enum SarrioFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Geist-Bold"
        case .semibold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }

    static func uiName(for weight: UIFont.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Geist-Bold"
        case .semibold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }
}

extension Font {
    /// Geist al tamaño dado; crece con el Tipo Dinámico del sistema.
    static func sarrio(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(SarrioFont.name(for: weight), size: size, relativeTo: size >= 22 ? .title : size >= 16 ? .body : .footnote)
    }

}

extension UIFont {
    static func sarrio(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: SarrioFont.uiName(for: weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Con cifras de ancho fijo (contadores que cambian).
    var monospacedDigits: UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType, UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
