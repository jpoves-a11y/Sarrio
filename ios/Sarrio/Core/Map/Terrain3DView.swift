import CoreLocation
@_spi(Experimental) import MapboxMaps
import SarrioKit
import SwiftUI
import UIKit

/// Relieve 3D real (Mapbox Standard Satellite con terreno) con la ruta y las cumbres encima.
///
/// Nunca se ve a medio cargar: tras una cortina, el mapa carga en detalle la vista desde cuatro
/// ángulos de la órbita (como el replay, con `MapLoadState`) y solo entonces aparece y gira.
///
/// - `orbit`: la cámara gira despacio alrededor del centro con el giro lento del replay de KM2
///   (desde parado hasta 5°/s en 3 s); se detiene al tocar el mapa.
/// - `interactive`: permite girar, inclinar y hacer zoom con los dedos.
struct Terrain3DView: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var distance: CLLocationDistance = 2_800
    var segments: [[CLLocationCoordinate2D]] = []
    var summits: [PeakRef] = []
    var orbit = true
    var interactive = true
    var pitch: Double = 62
    /// Sin animación (el feed): las banderillas ya clavadas y la ruta entera, sin que caigan.
    var animated = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapView {
        let mapView = ReplayScene.makeMapView(frame: .zero)
        ReplayScene.setInteractive(interactive, on: mapView)
        context.coordinator.attach(to: mapView, view: self)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleUIView(_ mapView: MapView, coordinator: Coordinator) {
        coordinator.cancelLoading()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var mapView: MapView?
        private var view: Terrain3DView?
        private var link: CADisplayLink?
        private var startTime: CFTimeInterval = 0
        private var baseHeading: Double = 20
        private var drawnKey = ""

        private let loadState = MapLoadState()
        private let cover = TerrainLoadingCover()
        private var revealTask: Task<Void, Never>?
        private var revealed = false
        private var flags: [SummitFlagView] = []

        private static let routeSource = "terrain-route"
        private static let casingLayer = "terrain-casing"
        private static let lineLayer = "terrain-line"

        func attach(to mapView: MapView, view: Terrain3DView) {
            self.mapView = mapView
            self.view = view
            loadState.attach(to: mapView)
            mapView.mapboxMap.setTileCacheBudget(size: .tiles(160))
            cover.frame = mapView.bounds
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mapView.addSubview(cover)
            mapView.mapboxMap.loadStyle(.standardSatellite) { [weak self] _ in
                MainActor.assumeIsolated { self?.styleLoaded() }
            }
            setCamera(heading: baseHeading)
            if view.interactive {
                for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
                    recognizer.addTarget(self, action: #selector(userGesture))
                    recognizer.delegate = self
                    recognizer.cancelsTouchesInView = false
                    mapView.addGestureRecognizer(recognizer)
                }
            }
        }

        func update(_ view: Terrain3DView) {
            let moved = self.view.map { $0.center.latitude != view.center.latitude || $0.center.longitude != view.center.longitude } ?? true
            self.view = view
            drawOverlays()
            if moved && revealed {
                // Otro pico en la misma vista: vuelve a cargar antes de enseñarlo
                revealed = false
                stop()
                cover.show()
                setCamera(heading: baseHeading)
                prepareAndReveal()
            }
        }

        private func styleLoaded() {
            guard let map = mapView?.mapboxMap else { return }
            for (key, value) in ["showPointOfInterestLabels": false, "showTransitLabels": false, "showRoadLabels": false] as [String: Any] {
                try? map.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
            }
            ReplayScene.addTerrain(to: map)
            drawnKey = ""
            drawOverlays()
            prepareAndReveal()
        }

        /// Carga en detalle las vistas de la órbita (cuatro rumbos) y luego quita la cortina y gira.
        private func prepareAndReveal() {
            guard let mapView, let view else { return }
            revealTask?.cancel()
            let headings = view.orbit ? [baseHeading + 90, baseHeading + 180, baseHeading + 270, baseHeading] : [baseHeading]
            revealTask = Task { [weak self] in
                let clock = FrameClock(rate: 60)
                clock.start()
                defer { clock.stop() }
                // Que el mapa esté en pantalla
                var waited = 0
                while mapView.window == nil || mapView.bounds.width < 1, waited < 300 {
                    await clock.next()
                    waited += 1
                }
                guard let self else { return }
                for heading in headings {
                    if Task.isCancelled { return }
                    self.setCamera(heading: heading)
                    _ = await self.loadState.settle(clock: clock, maxSeconds: 4, minRefreshes: 3)
                }
                if Task.isCancelled { return }
                self.revealed = true
                self.cover.hide()
                // Las banderas caen y se clavan al aparecer el relieve, una tras otra
                if self.view?.animated != false {
                    for (i, flag) in self.flags.enumerated() { flag.plant(delay: 0.35 + Double(i) * 0.25) }
                }
                if self.view?.orbit == true { self.startOrbit() }
            }
        }

        /// La ruta (borde blanco y línea de acento) y las cumbres.
        private func drawOverlays() {
            guard let view, let mapView, let map = mapView.mapboxMap, map.isStyleLoaded else { return }
            let key = "\(view.segments.map(\.count))-\(view.summits.map(\.id))"
            guard key != drawnKey else { return }
            drawnKey = key
            for layer in [Self.lineLayer, Self.casingLayer] where map.layerExists(withId: layer) { try? map.removeLayer(withId: layer) }
            if map.sourceExists(withId: Self.routeSource) { try? map.removeSource(withId: Self.routeSource) }
            mapView.viewAnnotations.removeAll()

            let lines = view.segments.filter { $0.count >= 2 }
            if !lines.isEmpty {
                var source = GeoJSONSource(id: Self.routeSource)
                source.data = .geometry(.multiLineString(MultiLineString(lines)))
                try? map.addSource(source)
                var casing = LineLayer(id: Self.casingLayer, source: Self.routeSource)
                casing.lineColor = .constant(StyleColor(UIColor.white.withAlphaComponent(0.95)))
                casing.lineWidth = .constant(7)
                casing.lineCap = .constant(.round)
                casing.lineJoin = .constant(.round)
                casing.lineEmissiveStrength = .constant(1)
                try? map.addLayer(casing)
                var line = LineLayer(id: Self.lineLayer, source: Self.routeSource)
                line.lineColor = .constant(StyleColor(UIColor(named: "AccentColor") ?? .systemOrange))
                line.lineWidth = .constant(4)
                line.lineCap = .constant(.round)
                line.lineJoin = .constant(.round)
                line.lineEmissiveStrength = .constant(1)
                try? map.addLayer(line)
            }
            flags = view.summits.map { peak in
                // Escondidas hasta que el relieve está cargado; entonces caen y se clavan
                let flag = SummitFlagView(name: peak.displayName, elevation: peak.ele, scale: view.animated ? 1.25 : 1.0, planted: !view.animated)
                mapView.viewAnnotations.add(flag.annotation(at: CLLocationCoordinate2D(latitude: peak.lat, longitude: peak.lon)))
                if revealed && view.animated { flag.plant(delay: 0.2) }
                return flag
            }
        }

        private func setCamera(heading: Double) {
            guard let view, let mapView else { return }
            let camera = ReplayCamera(center: GeoPoint(lat: view.center.latitude, lon: view.center.longitude),
                                      distance: view.distance, pitch: view.pitch, heading: heading)
            mapView.mapboxMap.setCamera(to: ReplayScene.cameraOptions(for: camera, viewHeight: max(mapView.bounds.height, 300)))
        }

        private func startOrbit() {
            link?.invalidate()
            startTime = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            // Giro lento: desde parado hasta 5°/s en 3 s (como el final del replay)
            let t = link.targetTimestamp - startTime
            let turned = t < 3 ? 5 * t * t / 6 : 5 * (t - 1.5)
            setCamera(heading: baseHeading + turned)
        }

        @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
            guard recognizer.state == .began, link != nil else { return }
            stop()
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        func cancelLoading() {
            revealTask?.cancel()
            stop()
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Cortina mientras el relieve carga: degradado oscuro y un indicador discreto; se va con un fundido.
final class TerrainLoadingCover: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let gradient = CAGradientLayer()

    init() {
        super.init(frame: .zero)
        gradient.colors = [UIColor(white: 0.16, alpha: 1).cgColor, UIColor(white: 0.07, alpha: 1).cgColor]
        layer.addSublayer(gradient)
        spinner.color = UIColor.white.withAlphaComponent(0.7)
        spinner.startAnimating()
        addSubview(spinner)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func show() {
        isHidden = false
        alpha = 1
        spinner.startAnimating()
    }

    func hide() {
        UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
            self.spinner.stopAnimating()
        }
    }
}

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension PeakRef {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
