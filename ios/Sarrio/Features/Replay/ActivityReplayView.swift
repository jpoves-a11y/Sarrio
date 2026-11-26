import MapboxMaps
import SarrioKit
import SwiftUI
import UIKit

/// Progreso del replay para las capas de SwiftUI (contadores, perfil). Solo ellas se redibujan
/// mientras se reproduce; el mapa no.
@MainActor
@Observable
final class ReplayProgress {
    /// 0…1 de la ruta recorrida.
    var fraction: Double = 0
    var isFinished = false
    /// 0…1 mientras se cargan las vistas antes de reproducir; nil al reproducir.
    var loading: Double?
}

/// Replay 3D de una actividad sobre satélite con relieve: empieza lejos, vuela hasta el inicio,
/// sigue al montañero (la cámara gira con la ruta y se frena al coronar), y acaba mostrando toda
/// la ruta con un giro lento. Con la luz del sol de aquel momento y el tiempo que hizo.
struct ActivityReplayView: View {
    let activityId: String
    let segments: [[TrackPoint]]
    let summits: [PeakRef]
    var start: Date?
    var end: Date?
    /// nil: ocupa todo el espacio (pantalla completa).
    var height: CGFloat? = 380
    var onExpand: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plan: ReplayPlan?
    @State private var progress = ReplayProgress()
    @State private var playToken = 0
    @State private var weather = ReplayWeather()

    init(activityId: String, segments: [[TrackPoint]], summits: [PeakRef], start: Date? = nil, end: Date? = nil,
         height: CGFloat? = 380, onExpand: (() -> Void)? = nil) {
        self.activityId = activityId
        self.segments = segments
        self.summits = summits
        self.start = start
        self.end = end
        self.height = height
        self.onExpand = onExpand
        _plan = State(initialValue: ReplayPlan(track: segments.flatMap { $0 }, summits: summits.map { GeoPoint(lat: $0.lat, lon: $0.lon) }))
    }

    var body: some View {
        ZStack {
            if let plan {
                ReplayMapRepresentable(
                    plan: plan, summits: summits, start: start, end: end, weather: weather,
                    playToken: playToken, reduceMotion: reduceMotion, progress: progress
                )
                ReplayLoadingCover(progress: progress)
                ReplayChrome(plan: plan, progress: progress, weather: weather, onReplay: { playToken += 1 }, onExpand: onExpand)
            } else {
                Rectangle().fill(Theme.Colors.separator)
                    .overlay(Text("Esta actividad no tiene ruta").font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary))
            }
        }
        .frame(height: height)
        .frame(maxHeight: height == nil ? .infinity : nil)
        .task(id: activityId) {
            guard let plan, let start else { return }
            weather = await ReplayWeatherLoader.load(activityId: activityId, center: plan.center.coordinate, start: start, end: end ?? start)
        }
        .accessibilityLabel("Animación de la ruta en 3D")
    }
}

// MARK: - Mapa (UIKit, Mapbox)

/// El mapa del replay, movido fotograma a fotograma por un solo reloj (CADisplayLink a la frecuencia
/// de la pantalla, hasta 120 Hz). Cada fotograma se calcula para el instante en que estará en
/// pantalla, y el montañero, la cámara y la línea avanzan juntos.
private struct ReplayMapRepresentable: UIViewRepresentable {
    let plan: ReplayPlan
    let summits: [PeakRef]
    let start: Date?
    let end: Date?
    let weather: ReplayWeather
    let playToken: Int
    let reduceMotion: Bool
    let progress: ReplayProgress

    func makeCoordinator() -> Coordinator { Coordinator(progress: progress) }

    func makeUIView(context: Context) -> MapView {
        let mapView = ReplayScene.makeMapView(frame: .zero)
        context.coordinator.attach(to: mapView)
        context.coordinator.play(plan: plan, summits: summits, start: start, end: end, reduceMotion: reduceMotion, on: mapView)
        context.coordinator.lastToken = playToken
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.setWeather(weather)
        if context.coordinator.lastToken != playToken {
            context.coordinator.lastToken = playToken
            context.coordinator.play(plan: plan, summits: summits, start: start, end: end, reduceMotion: reduceMotion, on: mapView)
        }
    }

    static func dismantleUIView(_ mapView: MapView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let progress: ReplayProgress
        private weak var mapView: MapView?
        private let loadState = MapLoadState()
        private var scene: ReplayScene?
        private var director: ReplayDirector?
        private var displayLink: CADisplayLink?
        private var preloadTask: Task<Void, Never>?
        private var startTime: CFTimeInterval = 0
        private var lastTick: CFTimeInterval = 0
        private var lastPublished: CFTimeInterval = 0
        private var reportedFinish = false
        private var userTookOver = false
        private var settled = false
        private var weather = ReplayWeather()
        private var preloadedKey: String?
        var lastToken = 0

        init(progress: ReplayProgress) { self.progress = progress }

        func attach(to mapView: MapView) {
            self.mapView = mapView
            loadState.attach(to: mapView)
            // Tras la llegada el mapa es del usuario: al tocarlo, el giro lento se detiene
            for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
                recognizer.addTarget(self, action: #selector(userGesture(_:)))
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                mapView.addGestureRecognizer(recognizer)
            }
        }

        func setWeather(_ weather: ReplayWeather) {
            self.weather = weather
            scene?.setWeather(weather)
        }

        /// Reproduce desde el principio: carga el estilo y la ruta, luego todas las vistas (tras la
        /// cortina) y entonces vuela.
        func play(plan: ReplayPlan, summits: [PeakRef], start: Date?, end: Date?, reduceMotion: Bool, on mapView: MapView) {
            stop()
            let timeline = ReplayTimeline(plan: plan)
            let scene = ReplayScene(timeline: timeline, color: UIColor(named: "AccentColor") ?? .systemOrange, summits: summits)
            scene.start = start
            scene.end = end
            scene.setWeather(weather)
            self.scene = scene
            director = ReplayDirector(timeline: timeline)
            reportedFinish = false
            userTookOver = false
            settled = false
            ReplayScene.setInteractive(false, on: mapView)
            scene.install(on: mapView)
            progress.fraction = 0
            progress.isFinished = false
            progress.loading = 0

            let key = "\(plan.points.count)-\(Int(plan.length))"
            var cameras: [ReplayCamera] = []
            let warm: [ReplayCamera]
            if reduceMotion {
                warm = [timeline.revealCamera(heading: 0)]
            } else {
                if preloadedKey != key { cameras = ReplayDirector.preloadCameras(for: timeline) }
                warm = ReplayDirector.startCameras(for: timeline)
            }
            let loadState = self.loadState
            preloadTask = Task { [weak self] in
                let loaded = await loadState.preload(cameras, warm: warm, on: mapView, scene: scene) { fraction in
                    self?.progress.loading = fraction
                }
                guard loaded, !Task.isCancelled, let self, self.scene === scene else { return }
                self.preloadedKey = key
                self.begin(timeline: timeline, scene: scene, reduceMotion: reduceMotion)
            }
        }

        private func begin(timeline: ReplayTimeline, scene: ReplayScene, reduceMotion: Bool) {
            preloadTask = nil
            withAnimation(.easeOut(duration: 0.35)) { progress.loading = nil }
            startTime = CACurrentMediaTime()
            lastTick = startTime
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
            if reduceMotion {
                // Toda la ruta de golpe, sin movimiento
                scene.setCamera(timeline.revealCamera(heading: 0))
                scene.drawTrail(to: timeline.plan.length)
                scene.updateSky(fraction: 1)
                finish()
                return
            }
            scene.setCamera(timeline.overviewCamera)
        }

        func stop() {
            preloadTask?.cancel()
            preloadTask = nil
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let scene, var director else { stop(); return }
            let now = link.targetTimestamp
            let dt = min(0.1, max(0, now - lastTick))
            lastTick = now
            if settled {
                // Quieto: solo el cristal (lluvia, nieve) sigue
                scene.updateHiker(dt: dt)
                return
            }
            let frame = director.frame(at: now - startTime, dt: dt)
            self.director = director
            if frame.isOver || (frame.isFinished && userTookOver) {
                scene.drawTrail(to: scene.plan.length)
                finish()
                return
            }
            scene.setHikerAlpha(frame.showsHiker ? 1 : 0, animated: true)
            if !userTookOver { scene.setCamera(frame.camera) }
            scene.drawTrail(to: frame.trail)
            scene.updateSky(fraction: frame.run / scene.plan.length)
            scene.updateHiker(dt: dt)
            if frame.isFinished && !reportedFinish {
                reportedFinish = true
                if let mapView { ReplayScene.setInteractive(true, on: mapView) }
            }
            publish(fraction: frame.run / scene.plan.length, finished: frame.isFinished)
        }

        private func finish() {
            settled = true
            reportedFinish = true
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            if let mapView { ReplayScene.setInteractive(true, on: mapView) }
            progress.fraction = 1
            progress.isFinished = true
        }

        /// Las capas de SwiftUI a ~12 Hz: suficiente para los contadores y ligero para el hilo principal.
        private func publish(fraction: Double, finished: Bool) {
            let now = CACurrentMediaTime()
            guard finished != progress.isFinished || now - lastPublished > 1.0 / 12 else { return }
            lastPublished = now
            progress.fraction = fraction
            progress.isFinished = finished
        }

        @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
            if reportedFinish, recognizer.state == .began { userTookOver = true }
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Capas

/// Cortina mientras el mapa carga todas las vistas del replay, con cuánto lleva.
private struct ReplayLoadingCover: View {
    var progress: ReplayProgress

    var body: some View {
        if let loading = progress.loading {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: Theme.Spacing.m) {
                    ProgressRing(fraction: loading).frame(width: 46, height: 46)
                    Text("Preparando el vuelo…")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .transition(.opacity)
        }
    }
}

/// Un aro que se llena en sentido horario desde arriba.
struct ProgressRing: View {
    var fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
        }
    }
}

/// Contadores, perfil de elevación y botones sobre el mapa. Lee el progreso en su propio cuerpo,
/// así que se redibuja varias veces por segundo sin tocar el mapa.
private struct ReplayChrome: View {
    let plan: ReplayPlan
    var progress: ReplayProgress
    let weather: ReplayWeather
    var onReplay: () -> Void
    var onExpand: (() -> Void)?

    var body: some View {
        let distance = plan.length * progress.fraction
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: Theme.Spacing.m) {
                    counter(value: (distance / 1000).formatted(.number.precision(.fractionLength(1))), unit: "km")
                    if let ele = plan.elevation(at: distance) {
                        counter(value: ele.groupedInteger, unit: "m")
                        counter(value: "+" + plan.elevationGain(upTo: distance).groupedInteger, unit: "m")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .environment(\.colorScheme, .dark)
                Spacer()
                if let onExpand {
                    roundButton("arrow.up.left.and.arrow.down.right", action: onExpand)
                }
            }
            Spacer()
            if plan.elevations.contains(where: { $0 != nil }) {
                ElevationProfileView(plan: plan, fraction: progress.fraction)
                    .frame(height: 54)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .environment(\.colorScheme, .dark)
            }
            HStack {
                if weather.hasWeather, let url = weather.legalURL {
                    Link(destination: url) {
                        Label("Tiempo", systemImage: "apple.logo")
                            .labelStyle(.titleAndIcon)
                            .font(.sarrio(11, .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                if progress.isFinished {
                    Button(action: onReplay) {
                        Label("Repetir", systemImage: "arrow.counterclockwise")
                            .font(.sarrio(14, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .elevation(.medium)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, Theme.Spacing.s)
        }
        .padding(Theme.Spacing.m)
        .animation(Theme.Motion.spring, value: progress.isFinished)
        .opacity(progress.loading == nil ? 1 : 0)
    }

    private func counter(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.sarrio(17, .bold).monospacedDigit()).foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(unit).font(.sarrio(11, .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Perfil de elevación: lo recorrido en color de acento con un relleno que se desvanece, lo que
/// queda fino y tenue, y un marcador donde va el montañero.
struct ElevationProfileView: View {
    let plan: ReplayPlan
    let fraction: Double
    /// Color de lo que queda por recorrer (blanco sobre el mapa, gris sobre una tarjeta).
    var baseColor: Color = .white.opacity(0.3)
    var showsMarker = true

    var body: some View {
        Canvas { context, size in
            let samples = 120
            let values = (0...samples).map { plan.elevation(at: plan.length * Double($0) / Double(samples)) ?? 0 }
            guard let lo = values.min(), let hi = values.max(), hi > lo else { return }
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(samples),
                        y: size.height - 4 - (size.height - 10) * CGFloat((values[i] - lo) / (hi - lo)))
            }
            var full = Path()
            full.move(to: point(0))
            for i in 1...samples { full.addLine(to: point(i)) }
            context.stroke(full, with: .color(baseColor), lineWidth: 1.2)

            let done = max(1, Int((Double(samples) * min(1, max(0, fraction))).rounded()))
            var walked = Path()
            walked.move(to: point(0))
            for i in 1...done { walked.addLine(to: point(i)) }
            var fill = walked
            fill.addLine(to: CGPoint(x: point(done).x, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [Theme.Colors.accent.opacity(0.55), Theme.Colors.accent.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(walked, with: .color(Theme.Colors.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            guard showsMarker else { return }
            let marker = point(done)
            context.fill(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)), with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)), with: .color(Theme.Colors.accent), lineWidth: 2)
        }
    }
}
