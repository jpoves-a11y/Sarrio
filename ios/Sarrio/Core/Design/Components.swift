import SwiftUI

/// Bloque blanco con borde suave: la unidad visual básica de la app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
    }
}

/// Estadística: valor grande + unidad, con etiqueta pequeña encima.
struct StatView: View {
    var label: String
    var value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.statLabel)
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.statValue).foregroundStyle(Theme.Colors.textPrimary)
                if let unit { Text(unit).font(.statUnit).foregroundStyle(Theme.Colors.textSecondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fila de estadísticas separadas por líneas verticales finas.
struct StatRow: View {
    var stats: [(label: String, value: String, unit: String?)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(Theme.Colors.separator).frame(width: 1, height: 36)
                        .padding(.horizontal, Theme.Spacing.m)
                }
                StatView(label: stat.label, value: stat.value, unit: stat.unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Botón principal: acento sólido, ancho completo.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Botón secundario: contorno fino.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Avatar circular con iniciales (las fotos llegarán con R2).
struct AvatarView: View {
    var name: String
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Circle()
            .fill(Theme.Colors.accent.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
            )
            .accessibilityHidden(true)
    }
}

/// Cabecera de sección discreta.
struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Estado vacío sobrio, con una acción opcional.
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Colors.textSecondary)
            VStack(spacing: Theme.Spacing.xs) {
                Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.primary).frame(maxWidth: 260)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

extension Double {
    /// "3.404" (separador de miles, sin decimales).
    var groupedInteger: String { Int(self.rounded()).formatted(.number.grouping(.automatic)) }
}
