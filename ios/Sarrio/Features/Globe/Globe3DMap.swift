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
/// Pico elegido en el globo: uno de los tuyos (con sus ascensiones) o uno del buscador.
struct GlobeSelection: Equatable {
    var peak: PeakRef
    var group: PeakGroup?
    var id: Int64 { peak.id }
}

struct Globe3DMap: UIViewRepresentable {
    var groups: [PeakGroup]
    /// Cimas aún por subir (p. ej. las que faltan de un reto de lista): banderillas grises.
    var pending: [PeakRef] = []
    /// Pico elegido (lo pone el mapa al tocar, o el buscador, y lo puede quitar la vista).
    @Binding var selected: GlobeSelection?
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
        context.coordinator.update(groups: groups, pending: pending, overviewToken: overviewToken)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.selected = $selected
        context.coordinator.update(groups: groups, pending: pending, overviewToken: overviewToken)
        context.coordinator.syncSelection(selected)
    }

    static func dismantleUIView(_ mapView: MapView, coordinator: Coordinator) {
        coordinator.stopAll()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var selected: Binding<GlobeSelection?>
        /// Marcador del pico elegido en el buscador si no es de los tuyos.
        private var searchMarker: ViewAnnotation?
        private weak var mapView: MapView?
        private var groups: [PeakGroup] = []
        private var pending: [PeakRef] = []
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
        private var spinPadding: UIEdgeInsets?
        private var shownSelection: Int64?
        private var cancelables: [AnyCancelable] = []

        private static let source = "globe-peaks"
        private static let clusterLayer = "globe-clusters"
        private static let peakLayer = "globe-peak"
        private static let peakLabelLayer = "globe-peak-label"
        private static let flagImage = "sarrio-flag"
        private static let groupImage = "sarrio-flag-group"
        private static let pendingImage = "sarrio-flag-pending"
        /// Gris de las cimas pendientes (el mismo de los emblemas bloqueados).
        static let pendingColor = UIColor(red: 0.62, green: 0.63, blue: 0.66, alpha: 1)

        init(selected: Binding<GlobeSelection?>) { self.selected = selected }

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

        func update(groups: [PeakGroup], pending: [PeakRef] = [], overviewToken: Int) {
            self.groups = groups
            self.pending = pending
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

            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            // Banderillas (el mismo dibujo que en el resto de mapas). Ondean animando las imágenes, no las
            // vistas: tres desfases para las sueltas (cada cumbre usa uno) y uno para los grupos
            renderFlagImages(at: 0)
            startWaving()
            // Pequeñas de lejos, tamaño real de cerca
            let iconSize = Exp(.interpolate) { Exp(.linear); Exp(.zoom); 2; 0.55; 8; 0.8; 12; 1.0 }

            // Grupos: un manojo de banderillas con el número al lado
            var clusters = SymbolLayer(id: Self.clusterLayer, source: Self.source)
            clusters.filter = Exp(.has) { "point_count" }
            clusters.iconImage = .constant(.name(Self.groupImage))
            clusters.iconAnchor = .constant(.bottom)
            clusters.iconSize = .expression(iconSize)
            clusters.iconPitchAlignment = .constant(.viewport)
            clusters.iconAllowOverlap = .constant(true)
            clusters.iconOpacityTransition = StyleTransition(duration: 0.3, delay: 0)
            clusters.iconEmissiveStrength = .constant(1)
            clusters.textField = .expression(Exp(.get) { "point_count_abbreviated" })
            clusters.textFont = .constant(["DIN Pro Bold", "Arial Unicode MS Bold"])
            clusters.textSize = .constant(15)
            clusters.textColor = .constant(StyleColor(.white))
            clusters.textHaloColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.6)))
            clusters.textHaloWidth = .constant(1.2)
            clusters.textAnchor = .constant(.left)
            clusters.textOffset = .constant([1.6, -2.4])
            clusters.textAllowOverlap = .constant(true)
            clusters.textEmissiveStrength = .constant(1)
            try? map.addLayer(clusters)

            // Cumbre suelta: una banderilla de pie sobre el relieve
            var peaks = SymbolLayer(id: Self.peakLayer, source: Self.source)
            peaks.filter = Exp(.not) { Exp(.has) { "point_count" } }
            peaks.iconImage = .expression(Exp(.get) { "flagImage" })
            peaks.iconAnchor = .constant(.bottom)
            peaks.iconSize = .expression(iconSize)
            peaks.iconPitchAlignment = .constant(.viewport)
            peaks.iconAllowOverlap = .constant(true)
            peaks.iconOpacityTransition = StyleTransition(duration: 0.3, delay: 0)
            peaks.iconEmissiveStrength = .constant(1)
            try? map.addLayer(peaks)

            // Nombre y altitud a la derecha del paño (de cerca)
            var labels = SymbolLayer(id: Self.peakLabelLayer, source: Self.source)
            labels.filter = Exp(.not) { Exp(.has) { "point_count" } }
            labels.textField = .expression(Exp(.get) { "label" })
            labels.textFont = .constant(["DIN Pro Medium", "Arial Unicode MS Regular"])
            labels.textSize = .constant(13)
            labels.textColor = .constant(StyleColor(.white))
            labels.textHaloColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.65)))
            labels.textHaloWidth = .constant(1.4)
            labels.textAnchor = .constant(.left)
            labels.textOffset = .constant([2.2, -2.4])
            labels.textOptional = .constant(true)
            labels.textOpacityTransition = StyleTransition(duration: 0.3, delay: 0)
            labels.textEmissiveStrength = .constant(1)
            labels.minZoom = 8
            try? map.addLayer(labels)
        }

        // MARK: Ondeado

        private var waveLink: CADisplayLink?
        private let waveStart = CACurrentMediaTime()
        private static let phases = 3

        private func renderFlagImages(at t: Double) {
            guard let map = mapView?.mapboxMap else { return }
            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            for k in 0..<Self.phases {
                try? map.addImage(SummitFlag.image(.single, color: accent, t: t, phase: Double(k) * 2.1), id: "\(Self.flagImage)-\(k)")
            }
            try? map.addImage(SummitFlag.image(.group, color: accent, t: t), id: Self.groupImage)
            if !pending.isEmpty {
                for k in 0..<Self.phases {
                    try? map.addImage(SummitFlag.image(.single, color: Self.pendingColor, t: t, phase: Double(k) * 2.1),
                                      id: "\(Self.pendingImage)-\(k)")
                }
            }
        }

        /// Unas 12 veces por segundo: suficiente para que ondeen sin cargar el mapa.
        private func startWaving() {
            waveLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(wave))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 12)
            link.add(to: .main, forMode: .common)
            waveLink = link
        }

        @objc private func wave(_ link: CADisplayLink) {
            renderFlagImages(at: link.targetTimestamp - waveStart)
        }

        /// Oculta en las capas la cumbre elegida (encima va su banderilla animada) o las vuelve a mostrar.
        private func hideInLayers(peakId: Int64?) {
            guard let map = mapView?.mapboxMap, styleReady else { return }
            let notCluster: [Any] = ["!", ["has", "point_count"]]
            let filter: [Any] = peakId.map { ["all", notCluster, ["!=", ["get", "peakId"], Double($0)]] } ?? notCluster
            try? map.setLayerProperty(for: Self.peakLayer, property: "filter", value: filter)
            try? map.setLayerProperty(for: Self.peakLabelLayer, property: "filter", value: filter)
        }

        private func draw() {
            guard styleReady, let map = mapView?.mapboxMap else { return }
            let key = groups.map { "\($0.id):\($0.ascents.count)" }.joined(separator: ",") + "|" + pending.map { "\($0.id)" }.joined(separator: ",")
            guard key != drawnKey else { return }
            drawnKey = key
            if !pending.isEmpty { renderFlagImages(at: CACurrentMediaTime() - waveStart) }
            let pendingFeatures = pending.map { peak -> Feature in
                var feature = Feature(geometry: .point(Point(peak.coordinate)))
                let ele = peak.ele.map { " · \(Int($0.rounded()).formatted()) m" } ?? ""
                feature.properties = [
                    "peakId": .number(Double(peak.id)),
                    "flagImage": .string("\(Self.pendingImage)-\(Int(peak.id % Int64(Self.phases)))"),
                    "label": .string(peak.displayName + ele),
                ]
                return feature
            }
            let features = pendingFeatures + groups.map { group -> Feature in
                var feature = Feature(geometry: .point(Point(group.peak.coordinate)))
                let ele = group.peak.ele.map { " · \(Int($0.rounded()).formatted()) m" } ?? ""
                feature.properties = [
                    "peakId": .number(Double(group.peak.id)),
                    "flagImage": .string("\(Self.flagImage)-\(Int(group.peak.id % Int64(Self.phases)))"),
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
            let coordinates = groups.map(\.peak.coordinate) + pending.map(\.coordinate)
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

        /// Vuelo a una cima: se acerca, se inclina y luego gira despacio a su alrededor (con la
        /// ficha del pico abajo, por eso el centro se desplaza hacia arriba).
        private func fly(to peak: PeakRef) {
            guard let mapView else { return }
            stopSpin()
            let bearing = mapView.mapboxMap.cameraState.bearing + 35
            let padding = UIEdgeInsets(top: 0, left: 0, bottom: 260, right: 0)
            let target = CameraOptions(center: peak.coordinate, padding: padding, zoom: 13.4, bearing: bearing, pitch: 66)
            mapView.camera.fly(to: target, duration: 3.0) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.selected.wrappedValue?.id == peak.id else { return }
                    self.startSpin(center: peak.coordinate, zoom: 13.4, pitch: 66, bearing: bearing, rotatesGlobe: false, padding: padding)
                }
            }
        }

        func syncSelection(_ selection: GlobeSelection?) {
            guard selection?.id != shownSelection else { return }
            shownSelection = selection?.id
            searchMarker?.remove()
            searchMarker = nil
            hideInLayers(peakId: selection?.id)
            guard let selection, let mapView else { return }
            // La elegida (tuya o del buscador): banderilla grande que cae y se clava mientras la cámara vuela
            let flag = SummitFlagView(name: nil, elevation: nil, scale: 1.6, planted: false)
            let annotation = flag.annotation(at: selection.peak.coordinate)
            mapView.viewAnnotations.add(annotation)
            searchMarker = annotation
            flag.plant(delay: 1.6)
            fly(to: selection.peak)
        }

        // MARK: Giro lento

        /// `rotatesGlobe`: gira la Tierra (cambia la longitud); si no, gira la cámara alrededor del centro.
        private func startSpin(center: CLLocationCoordinate2D, zoom: CGFloat, pitch: CGFloat, bearing: Double, rotatesGlobe: Bool,
                               padding: UIEdgeInsets? = nil) {
            stopSpin()
            spinPadding = padding
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

        func stopAll() {
            stopSpin()
            waveLink?.invalidate()
            waveLink = nil
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
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, padding: spinPadding, zoom: spinZoom,
                                                          bearing: spinBaseBearing + turned(link, rate: 4), pitch: spinPitch))
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
                        self.selected.wrappedValue = GlobeSelection(peak: group.peak, group: group)
                        return
                    }
                    if let value = feature.properties?["peakId"] ?? nil, case let .number(id) = value,
                       let peak = self.pending.first(where: { $0.id == Int64(id) }) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        self.selected.wrappedValue = GlobeSelection(peak: peak, group: nil)
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
