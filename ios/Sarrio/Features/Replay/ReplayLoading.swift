import MapboxMaps
import SarrioKit
import UIKit

/// Refrescos de pantalla a los que esperar (`await clock.next()`), con un CADisplayLink. Como en KM2.
@MainActor
final class FrameClock: NSObject {
    let rate: Int
    private var link: CADisplayLink?
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(rate: Int = 60) {
        self.rate = max(1, rate)
        super.init()
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        let rate = Float(self.rate)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        resumeAll()
    }

    func next() async {
        guard link != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting.append(continuation)
        }
    }

    @objc private func tick() { resumeAll() }

    private func resumeAll() {
        let continuations = waiting
        waiting = []
        for c in continuations { c.resume() }
    }
}

/// Cuándo ha terminado Mapbox de dibujar el mapa (todas las teselas, sin transiciones), a partir de
/// sus eventos de render. Con esto el replay recorre antes, tras una cortina, todas las vistas que
/// va a mostrar: al reproducirse no falta ninguna zona. Igual que en KM2.
@MainActor
final class MapLoadState {
    private var frames = 0
    private var completeFrames = 0
    private var idles = 0
    private(set) var errors = 0
    private var observers: [AnyCancelable] = []

    func attach(to mapView: MapView) {
        observers = [
            mapView.mapboxMap.onRenderFrameFinished.observe { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.frames += 1
                    if event.renderMode == .full { self.completeFrames += 1 }
                }
            },
            mapView.mapboxMap.onMapIdle.observe { [weak self] _ in
                MainActor.assumeIsolated { self?.idles += 1 }
            },
            mapView.mapboxMap.onMapLoadingError.observe { [weak self] _ in
                MainActor.assumeIsolated { self?.errors += 1 }
            },
        ]
    }

    /// Espera a que el mapa muestre lo último que se puso: al menos `minRefreshes` refrescos y luego
    /// hasta que Mapbox haya dibujado un fotograma completo (o quede en reposo). Como mucho `maxSeconds`.
    func settle(clock: FrameClock, maxSeconds: Double, minRefreshes: Int = 2) async -> Bool {
        let startFrames = frames, startComplete = completeFrames, startIdles = idles
        let maxRefreshes = max(minRefreshes, Int((maxSeconds * Double(clock.rate)).rounded()))
        var refreshes = 0
        while refreshes < maxRefreshes {
            await clock.next()
            if Task.isCancelled { return false }
            refreshes += 1
            guard refreshes >= minRefreshes else { continue }
            let complete = completeFrames > startComplete + 1 || idles > startIdles
            let untouched = frames == startFrames && refreshes >= minRefreshes + 1
            if complete || untouched { return true }
        }
        return false
    }

    /// Pasa el mapa por `cameras` (cada una hasta que Mapbox la tiene cargada y dibujada: hasta 4 s,
    /// la primera, amplia, hasta 5 s) y luego por `warm`, las del arranque, para que sean las más
    /// frescas. Tras tres vistas seguidas que no cargan con errores (sin red) deja de esperar.
    func preload(_ cameras: [ReplayCamera], warm: [ReplayCamera], on mapView: MapView, scene: ReplayScene,
                 onProgress: (Double) -> Void) async -> Bool {
        let clock = FrameClock(rate: 60)
        clock.start()
        defer { clock.stop() }
        var waited = 0
        while mapView.window == nil || mapView.bounds.width < 1 || (!scene.isReady && waited < 15 * clock.rate) {
            await clock.next()
            if Task.isCancelled { return false }
            waited += 1
        }
        let all = cameras + warm
        var failing = 0
        for (index, camera) in all.enumerated() {
            scene.setCamera(camera)
            let warming = index >= cameras.count
            let errorsBefore = errors
            let settled = await settle(clock: clock, maxSeconds: failing >= 3 ? 0.3 : (index == 0 ? 5 : 4), minRefreshes: warming ? 3 : 2)
            failing = !settled && errors > errorsBefore ? failing + 1 : 0
            if Task.isCancelled { return false }
            onProgress(Double(index + 1) / Double(all.count))
        }
        return true
    }
}
