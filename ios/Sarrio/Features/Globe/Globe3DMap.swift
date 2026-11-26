import CoreLocation
@_spi(Experimental) import MapboxMaps
import SarrioKit
import SwiftUI
import UIKit

/// El globo 3D de tus cumbres (Mapbox Standard Satellite con relieve y atmósfera):
///
/// - Al abrir, la Tierra gira despacio (giro lento del replay de KM2: 0 → 5°/s en 3 s) y luego la
///   cámara vuela inclinándose hasta tus cumbres.
/// - Las cumbres se agrupan en burbujas con el número; al tocar una, la cámara se acerca a ella.
/// - Al tocar una cumbre, vuela hasta la cima en 3D y se queda girando a su alrededor.
struct Globe3DMap: UIViewRepresentable {
    var groups: [PeakGroup]
    /// Pico elegido (lo pone el mapa al tocar y lo puede quitar la vista).
    @Binding var selected: PeakGroup?
    /// Cambia para volver a la vista de todas las cumbres.
    var overviewToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(selected: $selected) }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero, mapInitOptions: MapInitOptions(
            cameraOptions: CameraOptions(center: CLLocationCoordinate2D(latitude: 38, longitude: -4), zoom: 1.1, pitch: 0)
        ))
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .adaptive
        context.coordinator.attach(to: mapView)
        context.coordinator.update(groups: groups, overviewToken: overviewToken)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.selected = $selected
        context.coordinator.update(groups: groups, overviewToken: overviewToken)
        context.coordinator.syncSelection(selected)
    }

    static func dismantleUIView(_ mapView: MapView, coordinator: Coordinator) {
        coordinator.stopSpin()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var selected: Binding<PeakGroup?>
        private weak var mapView: MapView?
        private var groups: [PeakGroup] = []
        private var drawnKey = ""
        private var overviewToken = -1
        private var styleReady = false
        private var introDone = false
        private var spinLink: CADisplayLink?
        private var spinStart: CFTimeInterval = 0
        private var spinBaseBearing: Double = 0
        private var spinCenter: CLLocationCoordinate2D?
        private var spinZoom: CGFloat = 1.1
        private var spinPitch: CGFloat = 0
        private var shownSelection: Int64?
        private var cancelables: [AnyCancelable] = []

        private static let source = "globe-peaks"
        private static let clusterLayer = "globe-clusters"
        private static let clusterCountLayer = "globe-cluster-count"
        private static let peakLayer = "globe-peak"
        private static let peakLabelLayer = "globe-peak-label"

        init(selected: Binding<PeakGroup?>) { self.selected = selected }

        func attach(to mapView: MapView) {
            self.mapView = mapView
            mapView.mapboxMap.loadStyle(.standardSatellite) { [weak self] _ in
                MainActor.assumeIsolated { self?.styleLoaded() }
            }
            cancelables.append(mapView.gestures.onMapTap.observe { [weak self] context in
                MainActor.assumeIsolated { self?.tapped(at: context.point) }
            })
            // Cualquier gesto del usuario para el giro: el mapa es suyo
            for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
                recognizer.addTarget(self, action: #selector(userGesture(_:)))
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                mapView.addGestureRecognizer(recognizer)
            }
            // La Tierra gira despacio mientras carga
            startSpin(center: CLLocationCoordinate2D(latitude: 38, longitude: -4), zoom: 1.1, pitch: 0, bearing: 0, rotatesGlobe: true)
        }

        private func styleLoaded() {
            guard let map = mapView?.mapboxMap else { return }
            for (key, value) in ["showPointOfInterestLabels": false, "showTransitLabels": false, "showRoadLabels": false] as [String: Any] {
                try? map.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
            }
            ReplayScene.addTerrain(to: map, exaggeration: 1.4)
            addLayers(to: map)
            styleReady = true
            drawnKey = ""
            draw()
            // Tras unos segundos de globo girando, vuela a tus cumbres
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.6))
                guard let self, !self.introDone else { return }
                self.introDone = true
                self.flyToOverview(duration: 4.2)
            }
        }

        func update(groups: [PeakGroup], overviewToken: Int) {
            self.groups = groups
            draw()
            if overviewToken != self.overviewToken {
                let first = self.overviewToken == -1
                self.overviewToken = overviewToken
                if !first {
                    selected.wrappedValue = nil
                    flyToOverview(duration: 2.6)
                }
            }
        }

        // MARK: Capas

        private func addLayers(to map: MapboxMap) {
            var source = GeoJSONSource(id: Self.source)
            source.data = .featureCollection(FeatureCollection(features: []))
            source.cluster = true
            source.clusterRadius = 46
            source.clusterMaxZoom = 11
            try? map.addSource(source)

            let accent = StyleColor(UIColor(named: "AccentColor") ?? .systemOrange)

            var clusters = CircleLayer(id: Self.clusterLayer, source: Self.source)
            clusters.filter = Exp(.has) { "point_count" }
            clusters.circleColor = .constant(accent)
            clusters.circleRadius = .expression(Exp(.step) { Exp(.get) { "point_count" }; 17; 5; 21; 20; 27 })
            clusters.circleStrokeColor = .constant(StyleColor(.white))
            clusters.circleStrokeWidth = .constant(3)
            clusters.circlePitchAlignment = .constant(.viewport)
            clusters.circleEmissiveStrength = .constant(1)
            try? map.addLayer(clusters)

            var count = SymbolLayer(id: Self.clusterCountLayer, source: Self.source)
            count.filter = Exp(.has) { "point_count" }
            count.textField = .expression(Exp(.get) { "point_count_abbreviated" })
            count.textFont = .constant(["DIN Pro Bold", "Arial Unicode MS Bold"])
            count.textSize = .constant(14)
            count.textColor = .constant(StyleColor(.white))
            count.textAllowOverlap = .constant(true)
            count.textEmissiveStrength = .constant(1)
            try? map.addLayer(count)

            var peaks = CircleLayer(id: Self.peakLayer, source: Self.source)
            peaks.filter = Exp(.not) { Exp(.has) { "point_count" } }
            peaks.circleColor = .constant(accent)
            peaks.circleRadius = .constant(8)
            peaks.circleStrokeColor = .constant(StyleColor(.white))
            peaks.circleStrokeWidth = .constant(3)
            peaks.circlePitchAlignment = .constant(.viewport)
            peaks.circleEmissiveStrength = .constant(1)
            try? map.addLayer(peaks)

            var labels = SymbolLayer(id: Self.peakLabelLayer, source: Self.source)
            labels.filter = Exp(.not) { Exp(.has) { "point_count" } }
            labels.textField = .expression(Exp(.get) { "label" })
            labels.textFont = .constant(["DIN Pro Medium", "Arial Unicode MS Regular"])
            labels.textSize = .constant(13)
            labels.textColor = .constant(StyleColor(.white))
            labels.textHaloColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.65)))
            labels.textHaloWidth = .constant(1.4)
            labels.textOffset = .constant([0, 1.5])
            labels.textAnchor = .constant(.top)
            labels.textOptional = .constant(true)
            labels.textEmissiveStrength = .constant(1)
            labels.minZoom = 8
            try? map.addLayer(labels)
        }

        private func draw() {
            guard styleReady, let map = mapView?.mapboxMap else { return }
            let key = groups.map { "\($0.id):\($0.ascents.count)" }.joined(separator: ",")
            guard key != drawnKey else { return }
            drawnKey = key
            let features = groups.map { group -> Feature in
                var feature = Feature(geometry: .point(Point(group.peak.coordinate)))
                let ele = group.peak.ele.map { " · \(Int($0.rounded()).formatted()) m" } ?? ""
                feature.properties = [
                    "peakId": .number(Double(group.peak.id)),
                    "label": .string(group.peak.displayName + ele),
                ]
                return feature
            }
            map.updateGeoJSONSource(withId: Self.source, data: .featureCollection(FeatureCollection(features: features)))
        }

        // MARK: Cámara

        /// Todas las cumbres en vista, inclinada para leer el relieve.
        private func flyToOverview(duration: TimeInterval) {
            guard let mapView else { return }
            stopSpin()
            let coordinates = groups.map(\.peak.coordinate)
            let target: CameraOptions
            if coordinates.count >= 2 {
                let padding = UIEdgeInsets(top: 120, left: 60, bottom: 220, right: 60)
                let fitted = (try? mapView.mapboxMap.camera(for: coordinates, camera: CameraOptions(bearing: 18, pitch: 50),
                                                            coordinatesPadding: padding, maxZoom: 11.5, offset: nil)) ?? CameraOptions()
                target = fitted
            } else if let only = coordinates.first {
                target = CameraOptions(center: only, zoom: 11.5, bearing: 18, pitch: 55)
            } else {
                // Sin cumbres aún: el globo sigue girando
                startSpin(center: CLLocationCoordinate2D(latitude: 38, longitude: -4), zoom: 1.1, pitch: 0, bearing: 0, rotatesGlobe: true)
                return
            }
            mapView.camera.fly(to: target, duration: duration) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let mapView = self.mapView, self.selected.wrappedValue == nil else { return }
                    let state = mapView.mapboxMap.cameraState
                    self.startSpin(center: state.center, zoom: state.zoom, pitch: state.pitch, bearing: state.bearing, rotatesGlobe: false)
                }
            }
        }

        /// Vuelo a una cima: se acerca, se inclina y luego gira despacio a su alrededor.
        private func fly(to group: PeakGroup) {
            guard let mapView else { return }
            stopSpin()
            let bearing = mapView.mapboxMap.cameraState.bearing + 35
            let target = CameraOptions(center: group.peak.coordinate, padding: UIEdgeInsets(top: 0, left: 0, bottom: 180, right: 0),
                                       zoom: 13.4, bearing: bearing, pitch: 66)
            mapView.camera.fly(to: target, duration: 3.0) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.selected.wrappedValue?.id == group.id else { return }
                    self.startSpin(center: group.peak.coordinate, zoom: 13.4, pitch: 66, bearing: bearing, rotatesGlobe: false)
                }
            }
        }

        func syncSelection(_ selection: PeakGroup?) {
            guard selection?.id != shownSelection else { return }
            shownSelection = selection?.id
            if let selection { fly(to: selection) }
        }

        // MARK: Giro lento

        /// `rotatesGlobe`: gira la Tierra (cambia la longitud); si no, gira la cámara alrededor del centro.
        private func startSpin(center: CLLocationCoordinate2D, zoom: CGFloat, pitch: CGFloat, bearing: Double, rotatesGlobe: Bool) {
            stopSpin()
            spinCenter = center
            spinZoom = zoom
            spinPitch = pitch
            spinBaseBearing = bearing
            spinStart = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: rotatesGlobe ? #selector(spinGlobe(_:)) : #selector(spinAround(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            spinLink = link
        }

        func stopSpin() {
            spinLink?.invalidate()
            spinLink = nil
        }

        /// Giro lento de KM2: desde parado hasta `rate`°/s en 3 s.
        private func turned(_ link: CADisplayLink, rate: Double) -> Double {
            let t = link.targetTimestamp - spinStart
            return t < 3 ? rate * t * t / 6 : rate * (t - 1.5)
        }

        @objc private func spinGlobe(_ link: CADisplayLink) {
            guard let mapView, let center = spinCenter else { return }
            var lon = center.longitude - turned(link, rate: 6)
            lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
            mapView.mapboxMap.setCamera(to: CameraOptions(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: lon),
                                                          zoom: spinZoom, pitch: spinPitch))
        }

        @objc private func spinAround(_ link: CADisplayLink) {
            guard let mapView, let center = spinCenter else { return }
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: spinZoom, bearing: spinBaseBearing + turned(link, rate: 4), pitch: spinPitch))
        }

        @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
            guard recognizer.state == .began else { return }
            stopSpin()
            introDone = true
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Toques

        private func tapped(at point: CGPoint) {
            guard let mapView else { return }
            let options = RenderedQueryOptions(layerIds: [Self.clusterLayer, Self.peakLayer, Self.peakLabelLayer], filter: nil)
            mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
                MainActor.assumeIsolated {
                    guard let self, let mapView = self.mapView else { return }
                    guard case let .success(features) = result, let feature = features.first?.queriedFeature.feature else {
                        return
                    }
                    if let value = feature.properties?["peakId"] ?? nil, case let .number(id) = value,
                       let group = self.groups.first(where: { $0.id == Int64(id) }) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        self.selected.wrappedValue = group
                        return
                    }
                    // Burbuja: acercarse hasta que se separe, inclinando la cámara
                    guard case let .point(point)? = feature.geometry else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.stopSpin()
                    mapView.mapboxMap.getGeoJsonClusterExpansionZoom(forSourceId: Self.source, feature: feature) { result in
                        MainActor.assumeIsolated {
                            let zoom: Double
                            if case let .success(extension_) = result, let value = extension_.value as? NSNumber {
                                zoom = value.doubleValue
                            } else {
                                zoom = Double(mapView.mapboxMap.cameraState.zoom) + 2
                            }
                            mapView.camera.fly(to: CameraOptions(center: point.coordinates, zoom: CGFloat(min(zoom + 0.6, 13)),
                                                                 bearing: mapView.mapboxMap.cameraState.bearing + 15, pitch: 55),
                                               duration: 1.8)
                        }
                    }
                }
            }
        }
    }
}
