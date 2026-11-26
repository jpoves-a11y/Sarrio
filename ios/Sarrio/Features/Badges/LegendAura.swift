import CoreMotion
import SwiftUI

/// Aura de las Leyendas, detrás del medallón:
/// - bloom dorado en dos capas (un filo de luz pegado al canto y un halo amplio que respira);
/// - rayos finos de distinta longitud, en dos coronas que giran en sentidos contrarios;
/// - llamas alrededor del canto, más altas arriba, con núcleo incandescente;
/// - polvo de oro que orbita y brasas que suben y se apagan.
/// `intensity` 0…1: apagada (aún no conseguida) o encendida del todo.
struct LegendAura: View {
    /// Diámetro del medallón (el aura ocupa bastante más).
    var size: CGFloat
    var intensity: Double = 1
    /// Sobre fondo oscuro la luz se suma (`plusLighter`); sobre blanco se pinta normal para que se vea.
    var onDark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lienzo del aura respecto al medallón.
    static let scale: CGFloat = 2

    var body: some View {
        let canvas = size * Self.scale
        Group {
            if reduceMotion {
                Bloom(size: size, t: 0, intensity: intensity)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                    ZStack {
                        Bloom(size: size, t: t, intensity: intensity)
                        Rays(size: size, t: t, intensity: intensity, onDark: onDark)
                        Fire(size: size, t: t, intensity: intensity, onDark: onDark)
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
    static let white = Color(red: 1.0, green: 0.97, blue: 0.88)
    static let core = Color(red: 1.0, green: 0.86, blue: 0.52)
    static let gold = Color(red: 0.93, green: 0.70, blue: 0.30)
    static let ember = Color(red: 1.0, green: 0.50, blue: 0.14)
}

/// Ruido suave y barato: suma de senos con fases por elemento.
private func noise(_ x: Double, _ seed: Double) -> Double {
    (sin(x * 2.1 + seed * 12.9) + sin(x * 3.7 + seed * 4.1) * 0.6 + sin(x * 5.3 + seed * 7.7) * 0.3) / 1.9
}

/// Bloom: filo de luz pegado al canto y halo amplio que respira.
private struct Bloom: View {
    var size: CGFloat
    var t: Double
    var intensity: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [AuraColors.core.opacity(0.55 * intensity), AuraColors.gold.opacity(0.22 * intensity), .clear],
                    center: .center, startRadius: size * 0.35, endRadius: size * 0.98
                ))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(1 + 0.045 * sin(t * 1.3))
                .blur(radius: size * 0.06)
            Circle()
                .stroke(AuraColors.white.opacity(0.85 * intensity), lineWidth: size * 0.035)
                .frame(width: size * 1.0, height: size * 1.0)
                .blur(radius: size * 0.035)
                .opacity(0.75 + 0.25 * sin(t * 2.2))
        }
    }
}

/// Dos coronas de rayos finos, de distinta longitud, que giran en sentidos contrarios.
private struct Rays: View {
    var size: CGFloat
    var t: Double
    var intensity: Double
    var onDark: Bool

    var body: some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            ctx.blendMode = onDark ? .plusLighter : .normal
            for layer in 0..<2 {
                let count = layer == 0 ? 18 : 26
                let spin = t * (layer == 0 ? 0.07 : -0.045)
                for i in 0..<count {
                    let seed = Double(i) * 1.618 + Double(layer) * 9
                    let a = Double(i) / Double(count) * 2 * .pi + spin
                    let len = size * (layer == 0 ? 0.42 : 0.28) * (0.65 + 0.35 * (0.5 + 0.5 * noise(t * 0.5, seed)))
                    let inner = size * 0.5
                    let width = size * (layer == 0 ? 0.012 : 0.007)
                    let p0 = CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner)
                    let p1 = CGPoint(x: c.x + cos(a) * (inner + len), y: c.y + sin(a) * (inner + len))
                    var path = Path()
                    path.move(to: p0)
                    path.addLine(to: p1)
                    let alpha = (layer == 0 ? 0.55 : 0.35) * intensity
                    ctx.stroke(path, with: .linearGradient(
                        Gradient(colors: [AuraColors.white.opacity(alpha), AuraColors.gold.opacity(alpha * 0.5), .clear]),
                        startPoint: p0, endPoint: p1
                    ), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        .blur(radius: size * 0.006)
    }
}

/// Llamas con núcleo incandescente, polvo de oro en órbita y brasas que suben.
private struct Fire: View {
    var size: CGFloat
    var t: Double
    var intensity: Double
    var onDark: Bool

    var body: some View {
        ZStack {
            // Capa exterior: llamas anchas y difuminadas
            flames(widthScale: 1, lengthScale: 1, colors: [AuraColors.core, AuraColors.ember, AuraColors.ember.opacity(0)], alpha: 0.75)
                .blur(radius: size * 0.022)
            // Núcleo: más fino, más corto, casi blanco
            flames(widthScale: 0.45, lengthScale: 0.6, colors: [AuraColors.white, AuraColors.core, AuraColors.core.opacity(0)], alpha: 0.9)
                .blur(radius: size * 0.006)
            sparks.blur(radius: size * 0.004)
        }
    }

    private func flames(widthScale: Double, lengthScale: Double, colors: [Color], alpha: Double) -> some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = size * 0.48
            ctx.blendMode = onDark ? .plusLighter : .normal
            let tongues = 40
            for i in 0..<tongues {
                let seed = Double(i) * 0.731
                let a = Double(i) / Double(tongues) * 2 * .pi + noise(t * 0.2, seed) * 0.05
                // 0 abajo … 1 arriba: el fuego tira hacia arriba
                let up = (1 - sin(a)) / 2
                let flicker = 0.5 + 0.5 * noise(t * 2.6, seed)
                let len = size * (0.05 + 0.2 * up * up) * (0.5 + 0.65 * flicker) * lengthScale
                let width = size * (0.045 + 0.03 * up) * widthScale
                let out = CGVector(dx: cos(a), dy: sin(a))
                let tangent = CGVector(dx: -out.dy, dy: out.dx)
                let base = CGPoint(x: c.x + out.dx * r, y: c.y + out.dy * r)
                let sway = noise(t * 3.3, seed + 3) * width * 1.1
                let tip = CGPoint(
                    x: base.x + out.dx * len + tangent.dx * sway,
                    y: base.y + out.dy * len * 0.7 - len * 0.55 * up + tangent.dy * sway
                )
                let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
                var path = Path()
                path.move(to: CGPoint(x: base.x - tangent.dx * width / 2, y: base.y - tangent.dy * width / 2))
                path.addQuadCurve(to: tip, control: CGPoint(x: mid.x - tangent.dx * width * 0.7, y: mid.y - tangent.dy * width * 0.7))
                path.addQuadCurve(to: CGPoint(x: base.x + tangent.dx * width / 2, y: base.y + tangent.dy * width / 2),
                                  control: CGPoint(x: mid.x + tangent.dx * width * 0.7, y: mid.y + tangent.dy * width * 0.7))
                path.closeSubpath()
                let o = (0.3 + 0.55 * flicker) * alpha * intensity
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: colors.enumerated().map { $0.element.opacity(o * (1 - Double($0.offset) * 0.25)) }),
                    startPoint: base, endPoint: tip
                ))
            }
        }
    }

    private var sparks: some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = size * 0.48
            ctx.blendMode = onDark ? .plusLighter : .normal
            // Polvo de oro en órbita (elipse inclinada, como un anillo alrededor del medallón)
            for i in 0..<28 {
                let seed = Double(i) * 2.399
                let speed = 0.25 + (seed.truncatingRemainder(dividingBy: 1)) * 0.35
                let a = seed + t * speed
                let orbit = size * (0.62 + 0.2 * (0.5 + 0.5 * sin(seed * 3)))
                let p = CGPoint(x: c.x + cos(a) * orbit, y: c.y + sin(a) * orbit * 0.42 - size * 0.05)
                // Las de detrás del medallón se ocultan
                let behind = sin(a) < 0 && abs(p.x - c.x) < r * 0.95
                guard !behind else { continue }
                let twinkle = 0.5 + 0.5 * sin(t * (3 + seed.truncatingRemainder(dividingBy: 2)) + seed)
                let d = size * (0.006 + 0.008 * twinkle)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)),
                         with: .color(AuraColors.white.opacity((0.35 + 0.65 * twinkle) * intensity)))
            }
            // Brasas que suben desde arriba y se apagan
            for i in 0..<20 {
                let seed = Double(i) * 1.37
                let life = 2.2 + (seed.truncatingRemainder(dividingBy: 1)) * 1.8
                let phase = ((t + seed * 3.1).truncatingRemainder(dividingBy: life)) / life
                let startA = -.pi / 2 + noise(seed, seed) * 1.0
                let start = CGPoint(x: c.x + cos(startA) * r, y: c.y + sin(startA) * r)
                let p = CGPoint(x: start.x + noise(t * 0.8 + seed, seed) * size * 0.1 * phase, y: start.y - size * 0.6 * phase)
                let fade = sin(phase * .pi)
                let d = size * (0.011 + 0.01 * (1 - phase))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)),
                         with: .color(AuraColors.core.opacity(0.95 * fade * intensity)))
            }
        }
    }
}

extension View {
    /// Pone el aura de Leyenda detrás (sin cambiar el tamaño de la vista).
    func legendAura(size: CGFloat, intensity: Double = 1, onDark: Bool = true) -> some View {
        background { LegendAura(size: size, intensity: intensity, onDark: onDark) }
    }

    /// El medallón sigue la inclinación del iPhone: gira un poco y un reflejo de luz recorre el metal.
    func motionSheen(enabled: Bool = true) -> some View {
        modifier(MotionSheen(enabled: enabled))
    }
}

// MARK: - Reflejo con el giroscopio

/// Actitud del iPhone, compartida por todas las vistas que la usan (se enciende solo mientras hay alguna).
@MainActor
@Observable
final class DeviceTilt {
    static let shared = DeviceTilt()
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            let gx = g.x, gy = g.y
            MainActor.assumeIsolated {
                // Inclinación respecto a sostenerlo de forma natural (algo levantado)
                self?.x = max(-1, min(1, gx * 1.6))
                self?.y = max(-1, min(1, (gy + 0.55) * 1.6))
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

private struct MotionSheen: ViewModifier {
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tilt = DeviceTilt.shared

    init(enabled: Bool) { self.enabled = enabled }

    func body(content: Content) -> some View {
        let active = enabled && !reduceMotion
        let x = active ? tilt.x : 0
        let y = active ? tilt.y : 0
        content
            .rotation3DEffect(.degrees(x * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(-y * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .overlay {
                if active {
                    GeometryReader { geo in
                        // Una mancha de luz que se desliza por el metal en sentido contrario a la inclinación
                        RadialGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .clear],
                                       center: UnitPoint(x: 0.5 - x * 0.45, y: 0.35 - y * 0.35),
                                       startRadius: 0, endRadius: geo.size.width * 0.45)
                            .blendMode(.plusLighter)
                            .clipShape(Circle())
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: x)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: y)
            .onChange(of: active, initial: true) { was, now in
                // `initial`: was == now en la primera llamada
                if now && (!was || was == now) { tilt.start() } else if !now && was { tilt.stop() }
            }
            .onDisappear { if active { tilt.stop() } }
    }
}
