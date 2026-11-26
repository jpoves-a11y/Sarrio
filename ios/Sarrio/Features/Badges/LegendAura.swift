import SwiftUI

/// Aura de las Leyendas, detrás del medallón: un halo dorado que respira, rayos que giran
/// despacio, una corona de llamas que lamen el canto y brasas que suben y se apagan.
/// `intensity` 0…1: apagada (aún no conseguida) o encendida del todo.
struct LegendAura: View {
    /// Diámetro del medallón (el aura ocupa bastante más).
    var size: CGFloat
    var intensity: Double = 1
    /// Sobre fondo oscuro la luz se suma (`plusLighter`); sobre blanco se pinta normal para que se vea.
    var onDark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lienzo del aura respecto al medallón.
    static let scale: CGFloat = 1.9

    var body: some View {
        let canvas = size * Self.scale
        Group {
            if reduceMotion {
                Halo(size: size, t: 0, intensity: intensity)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Halo(size: size, t: t, intensity: intensity)
                        Rays(size: size, t: t, intensity: intensity, onDark: onDark)
                        Flames(size: size, t: t, intensity: intensity, onDark: onDark)
                    }
                }
            }
        }
        .frame(width: canvas, height: canvas)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum AuraColors {
    static let core = Color(red: 1.0, green: 0.86, blue: 0.52)
    static let gold = Color(red: 0.93, green: 0.70, blue: 0.30)
    static let ember = Color(red: 1.0, green: 0.52, blue: 0.16)
}

/// Halo dorado que late despacio.
private struct Halo: View {
    var size: CGFloat
    var t: Double
    var intensity: Double

    var body: some View {
        let breathe = 1 + 0.05 * sin(t * 1.6)
        Circle()
            .fill(RadialGradient(
                colors: [AuraColors.core.opacity(0.75 * intensity), AuraColors.gold.opacity(0.38 * intensity), .clear],
                center: .center, startRadius: size * 0.3, endRadius: size * 0.92
            ))
            .frame(width: size * 1.85, height: size * 1.85)
            .scaleEffect(breathe)
            .blur(radius: size * 0.04)
    }
}

/// Rayos finos que giran: un abanico de luz detrás del medallón.
private struct Rays: View {
    var size: CGFloat
    var t: Double
    var intensity: Double
    var onDark: Bool

    var body: some View {
        let stops: [Gradient.Stop] = (0..<24).flatMap { i -> [Gradient.Stop] in
            let p = Double(i) / 24
            return [
                .init(color: .clear, location: p),
                .init(color: AuraColors.core.opacity(0.55 * intensity), location: p + 0.012),
                .init(color: .clear, location: p + 0.03),
            ]
        }
        Circle()
            .fill(AngularGradient(stops: stops, center: .center))
            .mask(Circle().fill(RadialGradient(colors: [.white, .white.opacity(0.5), .clear], center: .center,
                                                startRadius: size * 0.45, endRadius: size * 0.9)))
            .frame(width: size * 1.8, height: size * 1.8)
            .rotationEffect(.radians(t * 0.12))
            .blur(radius: 1.2)
            .blendMode(onDark ? .plusLighter : .normal)
            .opacity(onDark ? 1 : 0.7)
    }
}

/// Llamas alrededor del canto (más altas arriba, como un fuego que sube) y brasas que se elevan.
private struct Flames: View {
    var size: CGFloat
    var t: Double
    var intensity: Double
    var onDark: Bool

    /// Ruido suave y barato: suma de senos con fases por llama.
    private func noise(_ x: Double, _ seed: Double) -> Double {
        (sin(x * 2.1 + seed * 12.9) + sin(x * 3.7 + seed * 4.1) * 0.6 + sin(x * 5.3 + seed * 7.7) * 0.3) / 1.9
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let r = size * 0.47
            ctx.blendMode = onDark ? .plusLighter : .normal

            // Lenguas de fuego
            let tongues = 34
            for i in 0..<tongues {
                let seed = Double(i) * 0.731
                let a = Double(i) / Double(tongues) * 2 * .pi + noise(t * 0.2, seed) * 0.05
                // 0 abajo … 1 arriba: el fuego tira hacia arriba
                let up = (1 - sin(a)) / 2
                let flicker = 0.5 + 0.5 * noise(t * 2.4, seed)
                let len = size * (0.07 + 0.16 * up) * (0.55 + 0.6 * flicker)
                let width = size * (0.05 + 0.025 * up)
                let out = CGVector(dx: cos(a), dy: sin(a))
                let tangent = CGVector(dx: -out.dy, dy: out.dx)
                let base = CGPoint(x: c.x + out.dx * r, y: c.y + out.dy * r)
                // La punta se dobla hacia arriba y se mece
                let sway = noise(t * 3.1, seed + 3) * width * 0.9
                let tip = CGPoint(
                    x: base.x + out.dx * len + tangent.dx * sway,
                    y: base.y + out.dy * len * 0.75 - len * 0.45 * up + tangent.dy * sway
                )
                var path = Path()
                let l = CGPoint(x: base.x - tangent.dx * width / 2, y: base.y - tangent.dy * width / 2)
                let rr = CGPoint(x: base.x + tangent.dx * width / 2, y: base.y + tangent.dy * width / 2)
                let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
                path.move(to: l)
                path.addQuadCurve(to: tip, control: CGPoint(x: mid.x - tangent.dx * width * 0.6, y: mid.y - tangent.dy * width * 0.6))
                path.addQuadCurve(to: rr, control: CGPoint(x: mid.x + tangent.dx * width * 0.6, y: mid.y + tangent.dy * width * 0.6))
                path.closeSubpath()
                let alpha = (0.35 + 0.45 * flicker) * intensity
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [AuraColors.core.opacity(alpha), AuraColors.ember.opacity(alpha * 0.8), AuraColors.ember.opacity(0)]),
                    startPoint: base, endPoint: tip
                ))
            }

            // Brasas que suben desde el borde superior y se apagan
            let embers = 18
            for i in 0..<embers {
                let seed = Double(i) * 1.37
                let life = 2.2 + (seed.truncatingRemainder(dividingBy: 1)) * 1.6
                let phase = ((t + seed * 3.1).truncatingRemainder(dividingBy: life)) / life
                let startA = -.pi / 2 + noise(seed, seed) * 1.1
                let start = CGPoint(x: c.x + cos(startA) * r * 0.95, y: c.y + sin(startA) * r * 0.95)
                let rise = size * 0.55 * phase
                let drift = noise(t * 0.8 + seed, seed) * size * 0.08 * phase
                let p = CGPoint(x: start.x + drift, y: start.y - rise)
                let fade = sin(phase * .pi)
                let dot = size * (0.012 + 0.01 * (1 - phase))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(AuraColors.core.opacity(0.9 * fade * intensity)))
            }
        }
        .blur(radius: size * 0.012)
    }
}

extension View {
    /// Pone el aura de Leyenda detrás (sin cambiar el tamaño de la vista).
    func legendAura(size: CGFloat, intensity: Double = 1, onDark: Bool = true) -> some View {
        background { LegendAura(size: size, intensity: intensity, onDark: onDark) }
    }
}
