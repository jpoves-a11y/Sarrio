import CoreLocation
@_spi(Experimental) import MapboxMaps
import SarrioKit
import SwiftUI
import UIKit

/// Relieve 3D real (Mapbox Standard Satellite con terreno) con la ruta y las cumbres encima.
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
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var mapView: MapView?
        private var view: Terrain3DView?
        private var link: CADisplayLink?
        private var startTime: CFTimeInterval = 0
        private var baseHeading: Double = 20
        private var drawnKey = ""

        private static let routeSource = "terrain-route"
        private static let casingLayer = "terrain-casing"
        private static let lineLayer = "terrain-line"

        func attach(to mapView: MapView, view: Terrain3DView) {
            self.mapView = mapView
            self.view = view
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
            if view.orbit { startOrbit() }
        }

        func update(_ view: Terrain3DView) {
            let moved = self.view.map { $0.center.latitude != view.center.latitude || $0.center.longitude != view.center.longitude } ?? true
            self.view = view
            if moved {
                setCamera(heading: baseHeading)
                if view.orbit { startOrbit() }
            }
            drawOverlays()
        }

        private func styleLoaded() {
            guard let map = mapView?.mapboxMap else { return }
            for (key, value) in ["showPointOfInterestLabels": false, "showTransitLabels": false, "showRoadLabels": false] as [String: Any] {
                try? map.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
            }
            ReplayScene.addTerrain(to: map)
            drawnKey = ""
            drawOverlays()
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
            for peak in view.summits {
                let marker = SummitMarkerView(name: peak.displayName, elevation: peak.ele, color: UIColor(named: "AccentColor") ?? .systemOrange)
                let annotation = ViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: peak.lat, longitude: peak.lon), view: marker)
                annotation.variableAnchors = [ViewAnnotationAnchorConfig(anchor: .bottom)]
                annotation.allowOverlap = true
                mapView.viewAnnotations.add(annotation)
                marker.pop()
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

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Marcador simple de cumbre para SwiftUI (fuera de los mapas).
struct SummitPin: View {
    var body: some View {
        Image(systemName: "triangle.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.Colors.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .elevation(.medium)
    }
}

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension PeakRef {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
