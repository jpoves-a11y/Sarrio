import CoreLocation
@_spi(Experimental) import MapboxMaps
import SwiftUI
import UIKit

/// Imagen estática en 3D de una salida para el feed: satélite con relieve, el recorrido entero con
/// un trazo que resalta (halo blanco y línea de acento) y las banderillas de las cimas.
///
/// Se genera con el `Snapshotter` de Mapbox (sin un mapa vivo en la lista: nada que cargue a medias
/// ni que se mueva) y se guarda en el iPhone, así que solo se genera una vez por actividad y tamaño.
struct FeedRouteSnapshot: View {
    var activityId: String
    var segments: [[CLLocationCoordinate2D]]
    var peaks: [PeakRef]
    var height: CGFloat = 220

    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(white: 0.18), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    ProgressView().tint(.white.opacity(0.7))
                }
            }
            .frame(width: geo.size.width, height: height)
            .clipped()
            .task(id: "\(activityId)-\(Int(geo.size.width))") {
                guard geo.size.width > 10, image == nil else { return }
                let size = CGSize(width: geo.size.width, height: height)
                let rendered = await RouteSnapshotRenderer.shared.image(
                    id: activityId, size: size, scale: scale, segments: segments, peaks: peaks
                )
                withAnimation(.easeOut(duration: 0.35)) { image = rendered }
            }
        }
        .frame(height: height)
    }
}

/// Genera y guarda las imágenes, de una en una (el Snapshotter es pesado).
@MainActor
final class RouteSnapshotRenderer {
    static let shared = RouteSnapshotRenderer()

    private let memory = NSCache<NSString, UIImage>()
    private var running: Task<UIImage?, Never>?
    private lazy var folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "feed-maps", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Versión del dibujo: si cambia, se regeneran las imágenes guardadas.
    private static let version = 1

    func image(id: String, size: CGSize, scale: CGFloat, segments: [[CLLocationCoordinate2D]], peaks: [PeakRef]) async -> UIImage? {
        let key = "v\(Self.version)-\(id)-\(Int(size.width))x\(Int(size.height))@\(Int(scale))"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        let file = folder.appending(path: key + ".jpg")
        if let data = try? Data(contentsOf: file), let saved = UIImage(data: data, scale: scale) {
            memory.setObject(saved, forKey: key as NSString)
            return saved
        }
        // De una en una: espera a la anterior
        let previous = running
        let task = Task { @MainActor () -> UIImage? in
            _ = await previous?.value
            return await Self.render(size: size, scale: scale, segments: segments, peaks: peaks)
        }
        running = task
        guard let image = await task.value else { return nil }
        memory.setObject(image, forKey: key as NSString)
        if let data = image.jpegData(compressionQuality: 0.85) { try? data.write(to: file) }
        return image
    }

    private static func render(size: CGSize, scale: CGFloat, segments: [[CLLocationCoordinate2D]], peaks: [PeakRef]) async -> UIImage? {
        let coords = segments.flatMap { $0 }
        guard coords.count >= 2 else { return nil }
        let options = MapSnapshotOptions(size: size, pixelRatio: scale)
        let snapshotter = Snapshotter(options: options)

        // Estilo satélite, sin etiquetas, con relieve
        var observer: AnyCancelable?
        let loaded: Bool = await withCheckedContinuation { continuation in
            var resumed = false
            observer = snapshotter.onStyleLoaded.observeNext { _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: true)
            }
            snapshotter.styleURI = .standardSatellite
        }
        observer?.cancel()
        guard loaded else { return nil }
        for (key, value) in ["showPointOfInterestLabels": false, "showTransitLabels": false, "showRoadLabels": false,
                             "showPlaceLabels": false] as [String: Any] {
            try? snapshotter.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
        }
        ReplayScene.addTerrain(to: snapshotter, exaggeration: 1.4)

        // El recorrido: halo blanco ancho, línea de acento encima
        var source = GeoJSONSource(id: "feed-route")
        source.data = .geometry(.multiLineString(MultiLineString(segments.filter { $0.count >= 2 })))
        try? snapshotter.addSource(source)
        let accent = UIColor(named: "AccentColor") ?? .systemOrange
        var glow = LineLayer(id: "feed-route-glow", source: "feed-route")
        glow.lineColor = .constant(StyleColor(accent.withAlphaComponent(0.35)))
        glow.lineWidth = .constant(14)
        glow.lineBlur = .constant(6)
        glow.lineCap = .constant(.round)
        glow.lineJoin = .constant(.round)
        glow.lineEmissiveStrength = .constant(1)
        try? snapshotter.addLayer(glow)
        var casing = LineLayer(id: "feed-route-casing", source: "feed-route")
        casing.lineColor = .constant(StyleColor(.white))
        casing.lineWidth = .constant(7.5)
        casing.lineCap = .constant(.round)
        casing.lineJoin = .constant(.round)
        casing.lineEmissiveStrength = .constant(1)
        try? snapshotter.addLayer(casing)
        var line = LineLayer(id: "feed-route-line", source: "feed-route")
        line.lineColor = .constant(StyleColor(accent))
        line.lineWidth = .constant(4.5)
        line.lineCap = .constant(.round)
        line.lineJoin = .constant(.round)
        line.lineEmissiveStrength = .constant(1)
        try? snapshotter.addLayer(line)

        // Banderillas en las cimas
        if !peaks.isEmpty {
            try? snapshotter.addImage(SummitFlag.image(.single, scale: 1, color: accent), id: "feed-flag")
            var flags = GeoJSONSource(id: "feed-peaks")
            flags.data = .featureCollection(FeatureCollection(features: peaks.map { Feature(geometry: .point(Point($0.coordinate))) }))
            try? snapshotter.addSource(flags)
            var symbols = SymbolLayer(id: "feed-peaks", source: "feed-peaks")
            symbols.iconImage = .constant(.name("feed-flag"))
            symbols.iconAnchor = .constant(.bottom)
            symbols.iconAllowOverlap = .constant(true)
            symbols.iconPitchAlignment = .constant(.viewport)
            symbols.iconEmissiveStrength = .constant(1)
            try? snapshotter.addLayer(symbols)
        }

        // Encuadre: la ruta entera, el eje largo en horizontal, inclinada y con aire arriba
        let bearing = Terrain3DView.Coordinator.longAxisBearing(coords)
        let padding = UIEdgeInsets(top: 40, left: 22, bottom: 22, right: 22)
        var camera = snapshotter.camera(for: coords, padding: padding, bearing: bearing, pitch: 50)
        camera.zoom = camera.zoom.map { min($0, 15) }
        snapshotter.setCamera(to: camera)

        return await withCheckedContinuation { continuation in
            snapshotter.start(overlayHandler: nil) { result in
                // Mantiene vivo el snapshotter hasta aquí
                _ = snapshotter
                switch result {
                case let .success(image): continuation.resume(returning: image)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }
}
