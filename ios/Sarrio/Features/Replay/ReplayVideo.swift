import ActivityKit
import AVFoundation
import MapboxMaps
import Photos
import SarrioKit
import SwiftUI
import UIKit
import WeatherKit

// MARK: - El vídeo del replay

/// Cuánto lleva el vídeo, para la pantalla de progreso.
@MainActor
@Observable
final class ReplayVideoProgress {
    /// 0…1 del trabajo entero (cargar el mapa y luego los fotogramas)
    var fraction: Double = 0
    var isLoadingMap = true
    /// La app ha salido: el mapa no se dibuja en segundo plano, se sigue al volver
    var isPaused = false
    /// Segundos que faltan, en cuanto hay unos cuantos fotogramas hechos
    var remaining: Double?
}

/// Hace el vídeo del replay sin grabar la pantalla (portado del de KM2). La misma animación que en la
/// app (`ReplayDirector` y `ReplayScene`) se calcula fotograma a fotograma a 30 fps exactos, en un mapa
/// propio a la resolución de la pantalla (que Mapbox solo dibuja en pantalla: se ve, en pequeño, en la
/// pantalla de progreso):
/// 1. Primero se cargan todas las vistas por las que pasa el replay.
/// 2. Cada fotograma se prepara y espera a que Mapbox lo haya dibujado entero (teselas, relieve 3D,
///    la línea, las banderas); entonces se copia al vídeo con los datos y la marca de Sarrio encima.
/// Las banderas, el montañero y el tiempo sobre el cristal avanzan con el reloj del vídeo, no el real.
/// Si la app sale (o se bloquea el móvil), espera y sigue al volver sin perder lo hecho.
@MainActor
final class ReplayVideoRenderer {
    struct Job: Identifiable {
        let id = UUID()
        let plan: ReplayPlan
        let summits: [PeakRef]
        let start: Date?
        let end: Date?
        let weather: ReplayWeather
        let title: String
        /// Puntos de la pantalla y su escala: el vídeo sale a su resolución nativa
        let screenSize: CGSize
        let screenScale: CGFloat
    }

    enum RenderError: LocalizedError {
        case capture
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .capture: "No se ha podido dibujar el mapa del vídeo."
            case .writer(let reason): "No se ha podido crear el vídeo (\(reason))."
            }
        }
    }

    static let framesPerSecond: Int32 = 30
    /// Segundos tras la llegada: el principio del giro lento
    static let tail: Double = 3
    private static let loadingShare = 0.12

    let progress = ReplayVideoProgress()
    let live = VideoExportLive()
    let mapView: MapView
    let mapSize: CGSize
    let videoSize: CGSize

    private let job: Job
    private let timeline: ReplayTimeline
    private let scene: ReplayScene
    private var director: ReplayDirector
    private let loadState = MapLoadState()
    private let clock: FrameClock
    private var overlayCache: (key: String, image: CGImage)?
    private var weatherMark: UIImage?
    private var observers: [NSObjectProtocol] = []

    init(job: Job) {
        self.job = job
        let timeline = ReplayTimeline(plan: job.plan)
        self.timeline = timeline
        let scene = ReplayScene(timeline: timeline, color: UIColor(named: "AccentColor") ?? .systemOrange, summits: job.summits)
        scene.start = job.start
        scene.end = job.end
        scene.videoClock = true
        self.scene = scene
        director = ReplayDirector(timeline: timeline)
        // Resolución nativa de la pantalla, en píxeles pares (como pide el codificador)
        let scale = max(1, job.screenScale)
        let pixelsW = (job.screenSize.width * scale / 2).rounded(.down) * 2
        let pixelsH = (job.screenSize.height * scale / 2).rounded(.down) * 2
        videoSize = CGSize(width: max(2, pixelsW), height: max(2, pixelsH))
        mapSize = CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
        mapView = ReplayScene.makeMapView(frame: CGRect(origin: .zero, size: mapSize))
        let rate = max(60, UIScreen.main.maximumFramesPerSecond)
        clock = FrameClock(rate: rate)
        mapView.isUserInteractionEnabled = false
        mapView.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: Float(rate), preferred: Float(rate))
        mapView.mapboxMap.setTileCacheBudget(size: .tiles(320))
        loadState.attach(to: mapView)
        scene.setWeather(job.weather)
        scene.install(on: mapView)
        scene.setCamera(timeline.overviewCamera)
    }

    /// Segundos de vídeo.
    var duration: Double { timeline.total + Self.tail }

    /// Hace el vídeo y devuelve su archivo (en la carpeta temporal). Lanza CancellationError al cancelar.
    func render() async throws -> URL {
        UIApplication.shared.isIdleTimerDisabled = true
        live.start(title: job.title)
        watchAppState()
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers = []
        }
        do {
            let url = try await make()
            live.end(phase: .done)
            return url
        } catch {
            live.end(phase: error is CancellationError ? nil : .failed)
            throw error
        }
    }

    private func make() async throws -> URL {
        weatherMark = job.weather.hasWeather ? await Self.loadWeatherMark() : nil

        // 1. Todas las vistas del replay cargadas antes del primer fotograma
        await waitUntilActive()
        let cameras = ReplayDirector.preloadCameras(for: timeline)
        let warm = ReplayDirector.startCameras(for: timeline)
        let progress = self.progress
        let live = self.live
        let loaded = await loadState.preload(cameras, warm: warm, on: mapView, scene: scene) { fraction in
            progress.fraction = fraction * Self.loadingShare
            live.update(phase: .loading, fraction: progress.fraction, remaining: nil)
        }
        try Task.checkCancellation()
        guard loaded else { throw CancellationError() }
        progress.isLoadingMap = false

        // 2. El archivo
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sarrio-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let pixels = videoSize.width * videoSize.height
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(min(40_000_000, max(10_000_000, pixels * 7))),
            AVVideoExpectedSourceFrameRateKey: Int(Self.framesPerSecond),
            AVVideoMaxKeyFrameIntervalKey: Int(Self.framesPerSecond),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let colors: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: colors,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(videoSize.width),
            kCVPixelBufferHeightKey as String: Int(videoSize.height),
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw RenderError.writer("formato") }
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.writer(writer.error?.localizedDescription ?? "inicio") }
        writer.startSession(atSourceTime: .zero)
        var completed = false
        defer {
            if !completed {
                if writer.status == .writing { writer.cancelWriting() }
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 3. Los fotogramas
        clock.start()
        defer { clock.stop() }
        let step = 1 / Double(Self.framesPerSecond)
        let frames = Int((duration / step).rounded(.up))
        var started = CACurrentMediaTime()
        var timedFrames = 0
        var failing = 0

        for index in 0..<frames {
            try Task.checkCancellation()
            let elapsed = Double(index) * step
            let dt = index == 0 ? 0 : step
            let frame = director.frame(at: elapsed, dt: dt)
            apply(frame, dt: dt)
            let overlay = autoreleasepool { overlayImage(for: frame) }

            var buffer: CVPixelBuffer?
            while true {
                // Fuera de la app el mapa no se dibuja: se espera a volver y se repite este fotograma
                if await waitUntilActive() {
                    started = CACurrentMediaTime()
                    timedFrames = 0
                }
                let errorsBefore = loadState.errors
                let settled = await loadState.settle(clock: clock, maxSeconds: failing >= 5 ? 0.15 : (index == 0 ? 5 : 3), minRefreshes: 2)
                failing = !settled && loadState.errors > errorsBefore ? failing + 1 : 0
                try Task.checkCancellation()
                guard UIApplication.shared.applicationState == .active else { continue }

                var waits = 0
                while !input.isReadyForMoreMediaData {
                    waits += 1
                    guard waits < 1000, writer.status == .writing else {
                        throw RenderError.writer(writer.error?.localizedDescription ?? "codificador")
                    }
                    try await Task.sleep(nanoseconds: 4_000_000)
                }
                guard writer.status == .writing, let pool = adaptor.pixelBufferPool else {
                    throw RenderError.writer(writer.error?.localizedDescription ?? "escritura")
                }
                var created: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
                guard let created else { throw RenderError.writer("memoria") }

                var drew = autoreleasepool { draw(overlay: overlay, into: created, forcingUpdate: !settled) }
                var retries = 0
                while !drew && retries < 3 && UIApplication.shared.applicationState == .active {
                    retries += 1
                    _ = await loadState.settle(clock: clock, maxSeconds: 0.5)
                    try Task.checkCancellation()
                    drew = autoreleasepool { draw(overlay: overlay, into: created, forcingUpdate: true) }
                }
                // Si la app salió mientras tanto, el fotograma puede estar a medias: otra vez al volver
                guard UIApplication.shared.applicationState == .active else { continue }
                guard drew else { throw RenderError.capture }
                buffer = created
                break
            }
            guard let buffer else { continue }

            let time = CMTime(value: CMTimeValue(index), timescale: Self.framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw RenderError.writer(writer.error?.localizedDescription ?? "escritura")
            }

            progress.fraction = Self.loadingShare + (1 - Self.loadingShare) * Double(index + 1) / Double(frames)
            timedFrames += 1
            if timedFrames == 1 {
                started = CACurrentMediaTime()
            } else if timedFrames >= 15 {
                let perFrame = (CACurrentMediaTime() - started) / Double(timedFrames - 1)
                progress.remaining = perFrame * Double(frames - index - 1)
            }
            live.update(phase: .rendering, fraction: progress.fraction, remaining: progress.remaining)
            if frame.isOver { break }
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw RenderError.writer(writer.error?.localizedDescription ?? "cierre")
        }
        completed = true
        return url
    }

    // MARK: Pausa al salir de la app

    /// Avisa a la Live Activity en cuanto la app va a salir (luego ya no puede).
    private func watchAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress.isPaused = true
                let task = UIApplication.shared.beginBackgroundTask(withName: "Sarrio vídeo en pausa")
                self.live.update(phase: .paused, fraction: self.progress.fraction, remaining: nil, force: true) {
                    UIApplication.shared.endBackgroundTask(task)
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress.isPaused = false
                self.live.update(phase: self.progress.isLoadingMap ? .loading : .rendering, fraction: self.progress.fraction,
                                 remaining: nil, force: true)
            }
        })
    }

    /// Espera a que la app vuelva a estar activa. True si ha tenido que esperar.
    @discardableResult
    private func waitUntilActive() async -> Bool {
        guard UIApplication.shared.applicationState != .active else { return false }
        progress.isPaused = true
        while UIApplication.shared.applicationState != .active {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        progress.isPaused = false
        return true
    }

    // MARK: Fotogramas

    private func apply(_ frame: ReplayFrame, dt: Double) {
        scene.setHikerAlpha(frame.showsHiker ? 1 : 0, animated: true)
        scene.setCamera(frame.camera)
        scene.drawTrail(to: frame.trail)
        scene.updateSky(fraction: frame.run / max(1, timeline.plan.length))
        scene.updateHiker(dt: dt)
        scene.stepFlags(dt: dt)
    }

    private func draw(overlay: CGImage?, into buffer: CVPixelBuffer, forcingUpdate: Bool) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return false }
        let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)
        // El mapa con las banderas, el montañero, el tiempo y la atribución de Mapbox, como en pantalla
        _ = mapView.drawHierarchy(in: rect, afterScreenUpdates: forcingUpdate)
        guard !Self.isBlank(context) else { return false }
        if let overlay { UIImage(cgImage: overlay).draw(in: rect) }
        return true
    }

    private static func isBlank(_ context: CGContext) -> Bool {
        guard let data = context.data else { return true }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for i in 1...4 {
            for j in 1...4 {
                let offset = (context.height * j / 5) * context.bytesPerRow + (context.width * i / 5) * 4
                if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 { return false }
            }
        }
        return true
    }

    /// Los datos, el perfil y la marca de este fotograma (se rehace solo cuando cambian).
    private func overlayImage(for frame: ReplayFrame) -> CGImage? {
        let fraction = min(1, max(0, frame.run / max(1, timeline.plan.length)))
        let key = "\(Int(fraction * 2000))"
        if let overlayCache, overlayCache.key == key { return overlayCache.image }
        let width: CGFloat = 390
        let height = (width * videoSize.height / videoSize.width).rounded()
        let renderer = ImageRenderer(content: ReplayVideoOverlay(plan: timeline.plan, fraction: fraction, weatherMark: weatherMark)
            .frame(width: width, height: height)
            .environment(\.colorScheme, .dark))
        renderer.scale = videoSize.width / width
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        overlayCache = (key, image)
        return image
    }

    /// La marca oficial de Apple Weather (obligatoria si el vídeo muestra su tiempo), versión clara.
    private static func loadWeatherMark() async -> UIImage? {
        guard let attribution = try? await WeatherService.shared.attribution,
              let (data, _) = try? await URLSession.shared.data(from: attribution.combinedMarkDarkURL) else { return nil }
        return UIImage(data: data)
    }
}

/// Lo que va encima del mapa en el vídeo: cifras, perfil, marca de Sarrio y crédito del tiempo.
private struct ReplayVideoOverlay: View {
    let plan: ReplayPlan
    let fraction: Double
    let weatherMark: UIImage?

    var body: some View {
        let distance = plan.length * fraction
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 14) {
                    counter((distance / 1000).formatted(.number.precision(.fractionLength(1))), "km")
                    if let ele = plan.elevation(at: distance) {
                        counter(ele.groupedInteger, "m")
                        counter("+" + plan.elevationGain(upTo: distance).groupedInteger, "m")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                Spacer()
                SarrioWatermark(height: 26)
            }
            Spacer()
            if plan.elevations.contains(where: { $0 != nil }) {
                ElevationProfileView(plan: plan, fraction: fraction, baseColor: .white.opacity(0.55), filled: false, lineWidth: 3)
                    .frame(height: 64)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            }
            HStack {
                if let weatherMark {
                    Image(uiImage: weatherMark).resizable().scaledToFit().frame(height: 11).opacity(0.85)
                }
                Spacer()
            }
            .frame(height: 14)
            .padding(.top, 6)
            // Encima de la atribución de Mapbox (que queda abajo, en el mapa)
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
    }

    private func counter(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.sarrio(19, .semibold).monospacedDigit()).foregroundStyle(.white)
            Text(unit).font(.sarrio(12, .medium)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Live Activity

/// La Live Activity del vídeo: progreso en la pantalla de bloqueo y la isla dinámica.
@MainActor
final class VideoExportLive {
    private var activity: Activity<VideoExportAttributes>?
    private var lastSent: (phase: VideoExportAttributes.Phase, fraction: Double, at: Date)?

    func start(title: String) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = VideoExportAttributes.ContentState(phase: .loading, fraction: 0, remaining: nil)
        activity = try? Activity.request(attributes: VideoExportAttributes(title: title), content: .init(state: state, staleDate: nil))
        lastSent = (.loading, 0, .now)
    }

    /// Como mucho una vez por segundo (o al cambiar de fase).
    func update(phase: VideoExportAttributes.Phase, fraction: Double, remaining: Double?, force: Bool = false, done: (@MainActor () -> Void)? = nil) {
        guard let activity else { done?(); return }
        if !force, let lastSent, lastSent.phase == phase,
           Date.now.timeIntervalSince(lastSent.at) < 1 || abs(fraction - lastSent.fraction) < 0.005 {
            done?()
            return
        }
        lastSent = (phase, fraction, .now)
        let state = VideoExportAttributes.ContentState(phase: phase, fraction: fraction, remaining: remaining)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
            done?()
        }
    }

    /// nil: se quita al momento (cancelado).
    func end(phase: VideoExportAttributes.Phase?) {
        guard let activity else { return }
        self.activity = nil
        let state = VideoExportAttributes.ContentState(phase: phase ?? .failed, fraction: phase == .done ? 1 : lastSent?.fraction ?? 0, remaining: nil)
        let policy: ActivityUIDismissalPolicy = phase == nil ? .immediate : .after(.now.addingTimeInterval(10 * 60))
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
}

// MARK: - Pantalla del vídeo

/// Prepara el vídeo con el mapa dibujándose en directo y el progreso, y al acabar lo muestra con
/// «Guardar en Fotos» y «Compartir».
struct ReplayVideoScreen: View {
    let job: ReplayVideoRenderer.Job
    @Environment(\.dismiss) private var dismiss
    @State private var renderer: ReplayVideoRenderer?
    @State private var url: URL?
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var saving = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            HStack {
                Text(url == nil ? "Creando tu vídeo" : "Tu vídeo")
                    .font(.sarrio(22, .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button(url == nil && errorMessage == nil ? "Cancelar" : "Hecho") { close() }
                    .font(.sarrio(16, .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            if let url {
                LoopingVideo(url: url)
                    .aspectRatio(job.screenSize.width / max(1, job.screenSize.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                    .elevation(.high)
                    .frame(maxHeight: .infinity)
                doneActions(url)
            } else if let errorMessage {
                Spacer()
                EmptyStateView(icon: "exclamationmark.triangle", title: "No se pudo crear el vídeo", message: errorMessage)
                Spacer()
            } else if let renderer {
                // El mapa del vídeo dibujándose, en pequeño: así se ve cómo avanza
                ReplayVideoMapHost(renderer: renderer)
                    .aspectRatio(renderer.mapSize.width / max(1, renderer.mapSize.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                    .elevation(.high)
                    .frame(maxHeight: .infinity)
                ReplayVideoProgressPanel(progress: renderer.progress)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.page.ignoresSafeArea())
        .task { start() }
        .onDisappear {
            task?.cancel()
        }
    }

    private func start() {
        guard renderer == nil, url == nil else { return }
        let renderer = ReplayVideoRenderer(job: job)
        self.renderer = renderer
        task = Task {
            do {
                let made = try await renderer.render()
                withAnimation(Theme.Motion.spring) { url = made }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close() {
        task?.cancel()
        if let url { try? FileManager.default.removeItem(at: url) }
        dismiss()
    }

    private func doneActions(_ url: URL) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Button {
                Task {
                    saving = true
                    defer { saving = false }
                    guard await VideoLibrary.requestAccess() else {
                        errorMessage = "Sarrio no tiene permiso para guardar en Fotos. Actívalo en Ajustes."
                        return
                    }
                    saved = await VideoLibrary.save(url)
                    if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            } label: {
                Label(saved ? "Guardado en Fotos" : "Guardar en Fotos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
            }
            .buttonStyle(.primary)
            .disabled(saved || saving)
            ShareLink(item: url) {
                Label("Compartir", systemImage: "square.and.arrow.up")
                    .font(.sarrio(16, .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }
}

/// Porcentaje grande, barra fina y qué está pasando.
private struct ReplayVideoProgressPanel: View {
    let progress: ReplayVideoProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((progress.fraction * 100).rounded(.down)))")
                    .font(.sarrio(44, .bold).monospacedDigit())
                    .foregroundStyle(progress.isPaused ? Theme.Colors.textSecondary : Theme.Colors.accent)
                    .contentTransition(.numericText(value: progress.fraction))
                    .animation(Theme.Motion.spring, value: Int(progress.fraction * 100))
                Text("%").font(.sarrio(20, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(status)
                    .font(.sarrio(14, .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Colors.separator)
                    Rectangle()
                        .fill(progress.isPaused ? Theme.Colors.textSecondary : Theme.Colors.accent)
                        .frame(width: geo.size.width * min(1, max(0, progress.fraction)))
                        .animation(.easeOut(duration: 0.3), value: progress.fraction)
                }
            }
            .frame(height: 4)
            Text("Puedes salir de Sarrio o bloquear el móvil: se pausa y sigue al volver. Verás el progreso en la pantalla de bloqueo.")
                .font(.sarrio(13))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: String {
        if progress.isPaused { return "En pausa" }
        if progress.isLoadingMap { return "Cargando el mapa…" }
        if let remaining = progress.remaining, remaining > 0 {
            return remaining < 60 ? "Quedan \(Int(remaining.rounded())) s" : "Quedan \(Int((remaining / 60).rounded(.up))) min"
        }
        return "Preparando…"
    }
}

/// El vídeo terminado, en bucle y sin sonido.
private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - El mapa del vídeo en pantalla

/// Muestra el mapa del vídeo reducido, mientras se dibuja a su propio tamaño (los píxeles del vídeo):
/// el mapa solo se dibuja cuando está en pantalla.
struct ReplayVideoMapHost: UIViewRepresentable {
    let renderer: ReplayVideoRenderer

    func makeUIView(context: Context) -> ReplayVideoMapContainer {
        ReplayVideoMapContainer(mapView: renderer.mapView, mapSize: renderer.mapSize)
    }

    func updateUIView(_ uiView: ReplayVideoMapContainer, context: Context) {}
}

final class ReplayVideoMapContainer: UIView {
    private let scaler = UIView()
    private let mapView: MapView
    private let mapSize: CGSize

    init(mapView: MapView, mapSize: CGSize) {
        self.mapView = mapView
        self.mapSize = mapSize
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        scaler.bounds = CGRect(origin: .zero, size: mapSize)
        addSubview(scaler)
        mapView.frame = CGRect(origin: .zero, size: mapSize)
        scaler.addSubview(mapView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard mapSize.width > 0, mapSize.height > 0 else { return }
        let scale = min(bounds.width / mapSize.width, bounds.height / mapSize.height)
        scaler.bounds = CGRect(origin: .zero, size: mapSize)
        scaler.center = CGPoint(x: bounds.midX, y: bounds.midY)
        scaler.transform = scale > 0 ? CGAffineTransform(scaleX: scale, y: scale) : .identity
        mapView.frame = CGRect(origin: .zero, size: mapSize)
    }
}

// MARK: - Fotos

/// Guardar vídeos en Fotos (solo añadir: Sarrio no ve la fototeca).
enum VideoLibrary {
    static func requestAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default: return false
        }
    }

    static func save(_ url: URL) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }
}
