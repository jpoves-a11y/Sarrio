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
    @State private var videoJob: ReplayVideoRenderer.Job?

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
                // A pantalla completa el mapa llega a los bordes, pero los datos quedan dentro de la
                // zona segura (bajo la isla o la muesca y sobre el indicador de inicio)
                ReplayMapRepresentable(
                    plan: plan, summits: summits, start: start, end: end, weather: weather,
                    playToken: playToken, reduceMotion: reduceMotion, progress: progress
                )
                .ignoresSafeArea(edges: height == nil ? .all : [])
                ReplayLoadingCover(progress: progress)
                    .ignoresSafeArea(edges: height == nil ? .all : [])
                ReplayChrome(plan: plan, progress: progress, weather: weather, onReplay: { playToken += 1 }, onExpand: onExpand,
                             onVideo: { videoJob = makeVideoJob(plan) })
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
        .fullScreenCover(item: $videoJob) { job in
            ReplayVideoScreen(job: job)
        }
    }

    private func makeVideoJob(_ plan: ReplayPlan) -> ReplayVideoRenderer.Job {
        let top = summits.max { ($0.ele ?? 0) < ($1.ele ?? 0) }
        return ReplayVideoRenderer.Job(
            plan: plan, summits: summits, start: start, end: end, weather: weather,
            title: top?.displayName ?? "tu ruta",
            screenSize: UIScreen.main.bounds.size, screenScale: UIScreen.main.scale
        )
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
        // Antes de reproducir se cargan todas las vistas de la ruta (unas 60). Con la caché de teselas
        // por defecto (calculada para una sola pantalla) las primeras se expulsaban de memoria y, al
        // llegar a ellas, se veían sin detalle mientras volvían a cargar: que quepa el recorrido entero.
        // En teselas y no en MB: en MB, Mapbox comprime el satélite (ETC1) y pierde nitidez.
        mapView.mapboxMap.setTileCacheBudget(size: .tiles(320))
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
    var onVideo: (() -> Void)?

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
                SarrioWatermark()
                if let onExpand {
                    roundButton("arrow.up.left.and.arrow.down.right", action: onExpand)
                }
            }
            Spacer()
            if plan.elevations.contains(where: { $0 != nil }) {
                // Solo la línea, sin fondo ni marco: gruesa y con sombra para leerse sobre el mapa
                ElevationProfileView(plan: plan, fraction: progress.fraction, baseColor: .white.opacity(0.55), filled: false, lineWidth: 3)
                    .frame(height: 58)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            }
            HStack {
                if weather.hasWeather, weather.legalURL != nil {
                    AppleWeatherMark(onDark: true)
                }
                Spacer()
                if progress.isFinished, let onVideo {
                    Button(action: onVideo) {
                        Label("Vídeo", systemImage: "square.and.arrow.up")
                            .font(.sarrio(14, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .elevation(.medium)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
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
    /// Relleno degradado bajo lo recorrido (en las tarjetas); sobre el mapa, solo la línea.
    var filled = true
    var lineWidth: CGFloat = 2.2
    /// La línea coloreada por pendiente (de suave a muy dura), en el detalle de la actividad.
    var slopeColored = false

    static let samples = 120

    /// Alturas muestreadas a lo largo de la ruta (las mismas que dibuja la línea).
    static func values(_ plan: ReplayPlan) -> [Double] {
        (0...samples).map { plan.elevation(at: plan.length * Double($0) / Double(samples)) ?? 0 }
    }

    /// Punto de la línea para una fracción del recorrido, en un lienzo de `size`.
    static func point(at fraction: Double, values: [Double], size: CGSize) -> CGPoint? {
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return nil }
        let x = min(1, max(0, fraction)) * Double(samples)
        let i = Int(x), j = min(samples, i + 1), t = x - Double(i)
        let v = values[i] + (values[j] - values[i]) * t
        return CGPoint(x: size.width * CGFloat(x / Double(samples)),
                       y: size.height - 4 - (size.height - 10) * CGFloat((v - lo) / (hi - lo)))
    }

    var body: some View {
        Canvas { context, size in
            let samples = Self.samples
            let values = Self.values(plan)
            guard let lo = values.min(), let hi = values.max(), hi > lo else { return }
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(samples),
                        y: size.height - 4 - (size.height - 10) * CGFloat((values[i] - lo) / (hi - lo)))
            }
            var full = Path()
            full.move(to: point(0))
            for i in 1...samples { full.addLine(to: point(i)) }
            context.stroke(full, with: .color(baseColor), style: StrokeStyle(lineWidth: filled ? 1.2 : lineWidth * 0.75, lineCap: .round, lineJoin: .round))

            let done = max(1, Int((Double(samples) * min(1, max(0, fraction))).rounded()))
            var walked = Path()
            walked.move(to: point(0))
            for i in 1...done { walked.addLine(to: point(i)) }
            if filled {
                var fill = walked
                fill.addLine(to: CGPoint(x: point(done).x, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [Theme.Colors.accent.opacity(0.55), Theme.Colors.accent.opacity(0)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            if slopeColored {
                // Cada tramo con el color de su pendiente
                let step = plan.length / Double(samples)
                for i in 1...done {
                    var seg = Path()
                    seg.move(to: point(i - 1))
                    seg.addLine(to: point(i))
                    let grade = step > 0 ? (values[i] - values[i - 1]) / step * 100 : 0
                    context.stroke(seg, with: .color(SlopeColor.color(forGrade: grade)),
                                   style: StrokeStyle(lineWidth: lineWidth + 0.6, lineCap: .round, lineJoin: .round))
                }
            } else {
                context.stroke(walked, with: .color(Theme.Colors.accent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            guard showsMarker else { return }
            let marker = point(done)
            context.fill(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)), with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)), with: .color(Theme.Colors.accent), lineWidth: 2)
        }
    }
}


/// Marca de agua de Sarrio sobre el replay: el sarrio y la palabra, en claro y con sombra.
struct SarrioWatermark: View {
    var height: CGFloat = 22

    var body: some View {
        HStack(spacing: 5) {
            Image("SarrioMark").resizable().scaledToFit().frame(height: height)
            Image("Wordmark").resizable().scaledToFit().frame(height: height * 0.62)
        }
        .environment(\.colorScheme, .dark)
        .opacity(0.9)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .padding(.top, 6)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
