import SwiftUI

/// Bloque blanco que flota sobre el fondo gris: la unidad visual básica de la app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.m
    var elevation: Theme.Elevation = .low
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 0.5)
            )
            .elevation(elevation)
    }
}

/// Estilo de botón para tarjetas pulsables: se hunde e inclina en 3D al tocarla, con háptica.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .rotation3DEffect(.degrees(configuration.isPressed ? 4 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

/// Inclinación 3D que sigue al dedo (como una tarjeta física) y vuelve con un muelle al soltar.
struct InteractiveTilt: ViewModifier {
    var maxAngle: Double = 8
    @State private var tilt: CGSize = .zero

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .rotation3DEffect(.degrees(Double(-tilt.height) * maxAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(Double(tilt.width) * maxAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                // Simultáneo, para no bloquear el desplazamiento de la pantalla.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
                            tilt = CGSize(width: (value.location.x / w - 0.5) * 2, height: (value.location.y / h - 0.5) * 2)
                        }
                        .onEnded { _ in withAnimation(Theme.Motion.spring) { tilt = .zero } }
                )
        }
    }
}

extension View {
    func interactiveTilt(maxAngle: Double = 8) -> some View { modifier(InteractiveTilt(maxAngle: maxAngle)) }

    /// Profundidad al desplazar: los elementos que entran y salen de pantalla se alejan en 3D.
    func scrollDepth() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.55)
                .rotation3DEffect(.degrees(phase.value * -10), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
        }
    }

    /// Entrada escalonada: aparece desde abajo con un muelle (`index` marca el retraso).
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

private struct StaggeredAppear: ViewModifier {
    var index: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .onAppear {
                withAnimation(Theme.Motion.spring.delay(Double(min(index, 8)) * 0.05)) { visible = true }
            }
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
            .background(
                LinearGradient(colors: [Theme.Colors.accent.opacity(0.92), Theme.Colors.accent], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
            )
            .shadow(color: Theme.Colors.accent.opacity(configuration.isPressed ? 0.15 : 0.32), radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
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
