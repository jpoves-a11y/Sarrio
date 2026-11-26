import SwiftUI

/// El medallón de un emblema. Conseguido: el metal en color. Bloqueado: en gris, apagado, con un
/// anillo fino de acento alrededor que marca lo que llevas.
struct BadgeMedal: View {
    var icon: String
    var earned: Bool
    var progress: Double? = nil
    var size: CGFloat = 76
    /// Brillo que recorre el metal (en la ficha grande y en la celebración).
    var shine = false

    var body: some View {
        ZStack {
            Image(icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .grayscale(earned ? 0 : 1)
                .opacity(earned ? 1 : 0.42)
                .padding(earned ? 0 : size * 0.07)
                .overlay { if shine && earned { Shine().clipShape(Circle()).allowsHitTesting(false) } }
            if !earned, let progress, progress > 0 {
                Circle()
                    .stroke(Theme.Colors.separator, lineWidth: max(1.5, size * 0.025))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: max(1.5, size * 0.025), lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if !earned {
                Image(systemName: "lock")
                    .font(.system(size: size * 0.13, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.8))
                    .offset(y: size * 0.5 - size * 0.04)
                    .opacity((progress ?? 0) > 0 ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Destello diagonal que cruza el medallón cada pocos segundos.
private struct Shine: View {
    @State private var phase: CGFloat = -1.2

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: geo.size.width * 0.35, height: geo.size.height * 1.8)
                .rotationEffect(.degrees(28))
                .offset(x: phase * geo.size.width * 1.2, y: -geo.size.height * 0.4)
                .blendMode(.plusLighter)
        }
        .onAppear {
            // Recorrido largo: cruza el metal en la parte central y descansa fuera el resto del ciclo
            withAnimation(.easeInOut(duration: 3.2).delay(0.5).repeatForever(autoreverses: false)) { phase = 2.4 }
        }
    }
}
