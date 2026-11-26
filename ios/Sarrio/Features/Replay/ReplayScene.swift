import CoreLocation
@_spi(Experimental) import MapboxMaps
import SarrioKit
import UIKit

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// Lo que el replay dibuja sobre el mapa de Mapbox: satélite con relieve 3D, la ruta entera tenue,
/// la ruta recorrida (la misma línea recortada en la distancia del montañero), el inicio, el
/// montañero, las cumbres que aparecen al coronarlas, la luz del sol de aquel momento y el tiempo
/// que hizo sobre el cristal. Basado en `ReplayScene` de KM2 (sin la bandera).
@MainActor
final class ReplayScene {
    let timeline: ReplayTimeline
    let color: UIColor
    private let summits: [PeakRef]

    private static let routeSource = "replay-route"
    private static let startSource = "replay-start"
    static let demSource = "replay-dem"
    private static let ghostLayer = "replay-ghost"
    private static let casingLayer = "replay-casing"
    private static let lineLayer = "replay-line"
    private static let startLayer = "replay-start-dot"

    private weak var mapView: MapView?
    private let hiker = HikerDotView()
    private var hikerAnnotation: ViewAnnotation?
    private var summitMarkers: [(distance: Double, view: SummitFlagView)] = []
    private(set) var isReady = false
    private var lightPreset = "day"
    private var drawn: Double = 0
    private var hikerAlpha: CGFloat = 0
    private var hikerAlphaTarget: CGFloat = 0
    private var summitsShown = 0

    /// Cuándo se hizo la actividad (luz del sol y tiempo).
    var start: Date?
    var end: Date?
    private(set) var weather = ReplayWeather()
    private var weatherKey = ""
    private let wetGlass = WetGlassView()

    var plan: ReplayPlan { timeline.plan }

    init(timeline: ReplayTimeline, color: UIColor, summits: [PeakRef]) {
        self.timeline = timeline
        self.color = color
        self.summits = summits
    }

    /// Un mapa sin adornos (solo el logo y la atribución que exige Mapbox) y sin gestos.
    static func makeMapView(frame: CGRect) -> MapView {
        let mapView = MapView(frame: frame)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        setInteractive(false, on: mapView)
        return mapView
    }

    static func setInteractive(_ on: Bool, on mapView: MapView) {
        mapView.gestures.options.panEnabled = on
        mapView.gestures.options.pinchEnabled = on
        mapView.gestures.options.rotateEnabled = on
        mapView.gestures.options.pitchEnabled = on
        mapView.gestures.options.doubleTapToZoomInEnabled = on
        mapView.gestures.options.doubleTouchToZoomOutEnabled = on
        mapView.gestures.options.quickZoomEnabled = on
    }

    /// Carga Standard Satellite con relieve y pone la ruta encima. `isReady` al terminar.
    func install(on mapView: MapView) {
        self.mapView = mapView
        isReady = false
        drawn = 0
        summitsShown = 0
        mapView.viewAnnotations.removeAll()
        hikerAnnotation = nil
        summitMarkers = []
        weatherKey = ""
        wetGlass.reset()
        wetGlass.frame = mapView.bounds
        wetGlass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if wetGlass.superview !== mapView { mapView.addSubview(wetGlass) }
        mapView.bringSubviewToFront(wetGlass)

        lightPreset = sunPreset(atFraction: 0) ?? "day"
        let style: StyleURI = .standardSatellite
        if mapView.mapboxMap.styleURI == style && mapView.mapboxMap.isStyleLoaded {
            addRoute(to: mapView)
            return
        }
        mapView.mapboxMap.loadStyle(style) { [weak self, weak mapView] _ in
            MainActor.assumeIsolated {
                guard let self, let mapView, self.mapView === mapView else { return }
                self.addRoute(to: mapView)
            }
        }
    }

    /// Relieve 3D (exagerado un poco: las montañas se leen mejor) en cualquier mapa de Mapbox.
    static func addTerrain(to map: MapboxMap, exaggeration: Double = 1.3) {
        if !map.sourceExists(withId: demSource) {
            var dem = RasterDemSource(id: demSource)
            dem.url = "mapbox://mapbox.mapbox-terrain-dem-v1"
            dem.tileSize = 514
            try? map.addSource(dem)
        }
        var terrain = Terrain(sourceId: demSource)
        terrain.exaggeration = .constant(exaggeration)
        try? map.setTerrain(terrain)
    }

    private func addRoute(to mapView: MapView) {
        let map = mapView.mapboxMap!
        map.styleTransition = TransitionOptions(duration: 2.5, delay: 0)
        let config: [String: Any] = [
            "lightPreset": lightPreset,
            "showPointOfInterestLabels": false,
            "showTransitLabels": false,
            "showRoadLabels": false,
        ]
        for (key, value) in config { try? map.setStyleImportConfigProperty(for: "basemap", config: key, value: value) }
        for layer in [Self.startLayer, Self.lineLayer, Self.casingLayer, Self.ghostLayer] where map.layerExists(withId: layer) {
            try? map.removeLayer(withId: layer)
        }
        for source in [Self.routeSource, Self.startSource] where map.sourceExists(withId: source) {
            try? map.removeSource(withId: source)
        }
        Self.addTerrain(to: map)

        let coordinates = plan.points.map(\.coordinate)
        var route = GeoJSONSource(id: Self.routeSource)
        route.data = .geometry(.lineString(LineString(coordinates)))
        route.lineMetrics = true
        try? map.addSource(route)

        // Toda la ruta, tenue y discontinua
        var ghost = LineLayer(id: Self.ghostLayer, source: Self.routeSource)
        ghost.lineColor = .constant(StyleColor(UIColor.white.withAlphaComponent(0.55)))
        ghost.lineWidth = .constant(2)
        ghost.lineCap = .constant(.round)
        ghost.lineDasharray = .constant([1, 2.5])
        ghost.lineEmissiveStrength = .constant(1)
        try? map.addLayer(ghost)

        // Lo recorrido: borde blanco y la línea de acento, recortadas en la distancia del montañero
        var casing = LineLayer(id: Self.casingLayer, source: Self.routeSource)
        casing.lineColor = .constant(StyleColor(UIColor.white.withAlphaComponent(0.95)))
        casing.lineWidth = .constant(7.5)
        casing.lineCap = .constant(.round)
        casing.lineJoin = .constant(.round)
        casing.lineTrimOffset = .constant([0, 1])
        casing.lineEmissiveStrength = .constant(1)
        try? map.addLayer(casing)

        var line = LineLayer(id: Self.lineLayer, source: Self.routeSource)
        line.lineColor = .constant(StyleColor(color))
        line.lineWidth = .constant(4.5)
        line.lineCap = .constant(.round)
        line.lineJoin = .constant(.round)
        line.lineTrimOffset = .constant([0, 1])
        line.lineEmissiveStrength = .constant(1)
        try? map.addLayer(line)

        var start = GeoJSONSource(id: Self.startSource)
        start.data = .geometry(.point(Point(coordinates.first ?? plan.center.coordinate)))
        try? map.addSource(start)
        var dot = CircleLayer(id: Self.startLayer, source: Self.startSource)
        dot.circleRadius = .constant(5)
        dot.circleColor = .constant(StyleColor(.white))
        dot.circleStrokeColor = .constant(StyleColor(color))
        dot.circleStrokeWidth = .constant(3)
        dot.circlePitchAlignment = .constant(.viewport)
        dot.circleEmissiveStrength = .constant(1)
        try? map.addLayer(dot)

        // El montañero, en el extremo de la línea (Mapbox lo apoya sobre el relieve)
        let annotation = ViewAnnotation(coordinate: coordinates.first ?? plan.center.coordinate, view: hiker)
        annotation.allowOverlap = true
        mapView.viewAnnotations.add(annotation)
        hikerAnnotation = annotation
        hiker.alpha = hikerAlpha

        // Las cumbres, escondidas hasta coronarlas
        for (index, distance) in plan.summitDistances.enumerated() where index < summits.count {
            let peak = summitForDistance(index)
            // Escondida arriba: cae y se clava cuando el montañero corona
            let view = SummitFlagView(name: peak.displayName, elevation: peak.ele, color: color, planted: false)
            mapView.viewAnnotations.add(view.annotation(at: CLLocationCoordinate2D(latitude: peak.lat, longitude: peak.lon)))
            summitMarkers.append((distance, view))
        }

        isReady = true
        applyWeather(at: date(atFraction: 0))
        let distance = drawn
        drawn = -1
        drawTrail(to: distance)
    }

    /// Cumbres ordenadas como `plan.summitDistances` (las dos listas vienen de la misma actividad).
    private lazy var orderedSummits: [PeakRef] = {
        summits.map { peak -> (PeakRef, Double) in
            var best = (index: 0, d: Double.infinity)
            for (i, p) in plan.points.enumerated() {
                let d = SarrioKit.Geo.distance(p.lat, p.lon, peak.lat, peak.lon)
                if d < best.d { best = (i, d) }
            }
            return (peak, plan.cumulative[best.index])
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }()

    private func summitForDistance(_ index: Int) -> PeakRef { orderedSummits[index] }

    // MARK: Cámara y línea

    func setCamera(_ camera: ReplayCamera) {
        guard let mapView else { return }
        mapView.mapboxMap.setCamera(to: Self.cameraOptions(for: camera, viewHeight: mapView.bounds.height))
    }

    /// La cámara de Mapbox para una del replay: el zoom al que el centro está a `distance` metros
    /// (el campo de visión de Mapbox mide ~36,87° de alto: la cámara está a 1,5 alturas de vista).
    static func cameraOptions(for camera: ReplayCamera, viewHeight: CGFloat) -> CameraOptions {
        let height = Double(max(100, viewHeight))
        let metresPerPointAtZoomZero = 40_075_016.686 * cos(camera.center.lat * .pi / 180) / 512
        let zoom = log2(metresPerPointAtZoomZero * 1.5 * height / max(1, camera.distance))
        return CameraOptions(
            center: camera.center.coordinate,
            zoom: CGFloat(min(22, max(0, zoom))),
            bearing: camera.heading,
            pitch: CGFloat(min(85, max(0, camera.pitch)))
        )
    }

    /// Dibuja la ruta hasta `distance` metros y hace aparecer las cumbres ya coronadas.
    func drawTrail(to distance: Double) {
        let target = min(max(0, distance), plan.length)
        guard isReady, let map = mapView?.mapboxMap, abs(target - drawn) > 0.01 else {
            if !isReady { drawn = target }
            return
        }
        drawn = target
        let fraction = plan.length > 0 ? target / plan.length : 0
        let trim: [Double] = fraction >= 1 ? [1, 1] : [fraction, 1]
        try? map.setLayerProperty(for: Self.casingLayer, property: "line-trim-offset", value: trim)
        try? map.setLayerProperty(for: Self.lineLayer, property: "line-trim-offset", value: trim)
        let reached = summitMarkers.filter { $0.distance <= target + 1 }.count
        if reached > summitsShown {
            for marker in summitMarkers[summitsShown..<reached] { marker.view.plant() }
            summitsShown = reached
        }
    }

    /// Mueve al montañero al extremo de la línea (después de `drawTrail`).
    func updateHiker(dt: Double) {
        if hikerAlpha != hikerAlphaTarget {
            let step = CGFloat(max(0, dt) / 0.25)
            hikerAlpha = hikerAlpha < hikerAlphaTarget ? min(hikerAlphaTarget, hikerAlpha + step) : max(hikerAlphaTarget, hikerAlpha - step)
        }
        hiker.alpha = hikerAlpha
        hikerAnnotation?.annotatedFeature = .geometry(Point(plan.coordinate(at: drawn).coordinate))
        wetGlass.step(dt: dt)
    }

    func setHikerAlpha(_ alpha: CGFloat, animated: Bool) {
        hikerAlphaTarget = alpha
        if !animated { hikerAlpha = alpha; hiker.alpha = alpha }
    }

    // MARK: Sol y tiempo

    func setWeather(_ weather: ReplayWeather) {
        guard weather != self.weather else { return }
        self.weather = weather
        weatherKey = ""
        applyWeather(at: date(atFraction: drawn / max(1, plan.length)))
    }

    /// La luz del sol (y el tiempo) cuando el montañero llevaba `fraction` de la ruta.
    func updateSky(fraction: Double) {
        guard isReady, let map = mapView?.mapboxMap else { return }
        if let preset = sunPreset(atFraction: fraction), preset != lightPreset {
            lightPreset = preset
            try? map.setStyleImportConfigProperty(for: "basemap", config: "lightPreset", value: preset)
        }
        applyWeather(at: date(atFraction: fraction))
    }

    private func date(atFraction fraction: Double) -> Date? {
        guard let start else { return nil }
        guard let end, end > start else { return start }
        return start.addingTimeInterval(end.timeIntervalSince(start) * min(1, max(0, fraction)))
    }

    private func sunPreset(atFraction fraction: Double) -> String? {
        guard let date = date(atFraction: fraction) else { return nil }
        return SunPosition.lightPreset(at: plan.coordinate(at: plan.length * fraction), date: date)
    }

    private func applyWeather(at date: Date?) {
        let hour = date.flatMap { weather.hour(at: $0) }
        let kind = hour?.kind ?? .dry
        let level = hour.map { $0.kind == .dry ? 0 : min(1, 0.3 + $0.amount / 5) } ?? 0
        let fog = hour?.fog ?? 0
        let key = "\(kind)-\(Int((level * 4).rounded()))-\(Int((fog * 10).rounded()))"
        guard key != weatherKey else { return }
        weatherKey = key
        wetGlass.setWeather(kind, level: level, fog: fog)
    }
}

// MARK: - Montañero y cumbres

/// El montañero: un punto de acento con aro blanco y un halo que late (sustituye a la bandera de KM2).
final class HikerDotView: UIView {
    private static let size: CGFloat = 44
    private let halo = CALayer()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isUserInteractionEnabled = false
        let core: CGFloat = 16
        halo.frame = bounds.insetBy(dx: (Self.size - core) / 2, dy: (Self.size - core) / 2)
        halo.cornerRadius = core / 2
        halo.backgroundColor = UIColor(named: "AccentColor")?.withAlphaComponent(0.45).cgColor
        layer.addSublayer(halo)

        let dot = UIView(frame: halo.frame)
        dot.backgroundColor = UIColor(named: "AccentColor") ?? .systemOrange
        dot.layer.cornerRadius = core / 2
        dot.layer.borderWidth = 3
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.35
        dot.layer.shadowRadius = 4
        dot.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(dot)
        startPulse()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func startPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.6
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        halo.add(group, forKey: "pulse")
    }

    override var intrinsicContentSize: CGSize { CGSize(width: Self.size, height: Self.size) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize { intrinsicContentSize }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize { intrinsicContentSize }
}
