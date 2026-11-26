import CoreLocation
import Foundation
import MapboxCommon
@_spi(Experimental) import MapboxMaps

/// Guarda en el iPhone, en segundo plano, lo que los mapas 3D necesitan para abrirse rápido:
///
/// - el estilo Standard Satellite (configuración, fuentes, iconos), para que ningún mapa lo espere;
/// - el globo a baja resolución (zoom 0-4), para la pestaña Globo;
/// - satélite y relieve alrededor de tus cumbres (unos 3 km, zoom 10-14), para el detalle del pico,
///   la cabecera de la biblioteca y el replay.
///
/// Las imágenes de satélite no pueden ir dentro de la app (lo impiden los términos de Mapbox):
/// se descargan con el sistema offline de Mapbox, solo con wifi y como mucho una vez al día.
@MainActor
final class MapPrefetcher {
    static let shared = MapPrefetcher()

    private let offline = OfflineManager()
    private var cancelables: [Cancelable] = []
    private var running = false
    private static let lastRunKey = "map.prefetch.lastRun"
    private static let lastPeaksKey = "map.prefetch.peaks"
    /// Cumbres más recientes con su zona guardada (las tiles cuentan en el uso de Mapbox).
    private static let maxPeaks = 40

    private init() {}

    /// Lo que el usuario ya ha visto se queda en el iPhone: el caché de teselas de Mapbox crece hasta
    /// 2 GB (por defecto es pequeño y se vacía pronto). Se llama al arrancar, antes de crear mapas.
    static func configureCache() {
        TileStore.default.setOptionForKey(TileStoreOptions.diskQuota, value: NSNumber(value: Int64(2) * 1024 * 1024 * 1024))
    }

    func prefetch(peaks: [PeakRef]) {
        guard !running else { return }
        let defaults = UserDefaults.standard
        let ids = peaks.prefix(Self.maxPeaks).map { String($0.id) }.joined(separator: ",")
        let last = defaults.double(forKey: Self.lastRunKey)
        // Una vez al día, salvo que haya cumbres nuevas
        if Date().timeIntervalSince1970 - last < 24 * 3600, defaults.string(forKey: Self.lastPeaksKey) == ids { return }
        running = true
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastRunKey)
        defaults.set(ids, forKey: Self.lastPeaksKey)

        if let packOptions = StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally, metadata: ["sarrio": "style"], acceptExpired: true) {
            cancelables.append(offline.loadStylePack(for: .standardSatellite, loadOptions: packOptions) { _ in })
        }

        // El globo entero a poca resolución
        let world = Polygon([[
            CLLocationCoordinate2D(latitude: -80, longitude: -180), CLLocationCoordinate2D(latitude: -80, longitude: 180),
            CLLocationCoordinate2D(latitude: 80, longitude: 180), CLLocationCoordinate2D(latitude: 80, longitude: -180),
            CLLocationCoordinate2D(latitude: -80, longitude: -180),
        ]])
        load(region: "sarrio-world", area: world, zoom: 0...4)

        // Alrededor de cada cumbre: satélite y relieve
        for peak in peaks.prefix(Self.maxPeaks) {
            load(region: "sarrio-peak-\(peak.id)", area: Self.square(around: peak.coordinate, meters: 3_000), zoom: 10...14)
        }
        running = false
    }

    private func load(region id: String, area: Polygon, zoom: ClosedRange<UInt8>) {
        let descriptor = offline.createTilesetDescriptor(for: TilesetDescriptorOptions(
            styleURI: .standardSatellite,
            zoomRange: zoom,
            tilesets: ["mapbox://mapbox.mapbox-terrain-dem-v1"]
        ))
        guard let options = TileRegionLoadOptions(
            geometry: .polygon(area),
            descriptors: [descriptor],
            metadata: ["sarrio": id],
            acceptExpired: true,
            networkRestriction: .disallowExpensive
        ) else { return }
        cancelables.append(TileStore.default.loadTileRegion(forId: id, loadOptions: options) { _ in })
    }

    private static func square(around center: CLLocationCoordinate2D, meters: Double) -> Polygon {
        let dLat = meters / 111_320
        let dLon = meters / (111_320 * max(cos(center.latitude * .pi / 180), 0.01))
        let sw = CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude - dLon)
        let ne = CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon)
        return Polygon([[
            sw, CLLocationCoordinate2D(latitude: sw.latitude, longitude: ne.longitude), ne,
            CLLocationCoordinate2D(latitude: ne.latitude, longitude: sw.longitude), sw,
        ]])
    }
}
