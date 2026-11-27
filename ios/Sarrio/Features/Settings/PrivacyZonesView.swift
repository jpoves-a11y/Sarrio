import CoreLocation
@_spi(Experimental) import MapboxMaps
import SwiftUI

/// Zonas privadas: círculos (casa, trabajo…) donde los demás no ven tus rutas. Mueve el mapa hasta
/// poner el punto de mira en el sitio, elige el radio y añade la zona.
struct PrivacyZonesView: View {
    @Environment(\.apiClient) private var api
    @Environment(LibraryStore.self) private var library
    @State private var zones: [PrivacyZone] = []
    @State private var center = CLLocationCoordinate2D(latitude: 40.42, longitude: -3.70)
    @State private var radius: Double = 500
    @State private var startCenter: CLLocationCoordinate2D?
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Quien vea tus salidas no verá el tramo de la ruta dentro de estas zonas. Tú siempre la ves entera.")
                    .font(.sarrio(15))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    if let startCenter {
                        PrivacyZonesMap(start: startCenter, zones: zones, pendingRadius: radius, center: $center)
                    }
                    // Punto de mira y el círculo que se va a añadir
                    Circle()
                        .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 18, height: 18)
                        .allowsHitTesting(false)
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Colors.accent)
                        .allowsHitTesting(false)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .elevation(.medium)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Radio").font(.sarrio(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(Int(radius)) m").font(.sarrio(15, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Slider(value: $radius, in: 200...1000, step: 50).tint(Theme.Colors.accent)
                    Button {
                        Task { await add() }
                    } label: {
                        if saving { ProgressView().tint(.white) } else { Text("Añadir zona aquí") }
                    }
                    .buttonStyle(.primary)
                    .disabled(saving || zones.count >= 10)
                    if let errorMessage {
                        Text(errorMessage).font(.sarrio(13)).foregroundStyle(.red)
                    }
                }

                if !zones.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: zones.count == 1 ? "1 zona" : "\(zones.count) zonas")
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: "eye.slash").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.Colors.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Zona \(index + 1)").font(.sarrio(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                                    Text("\(zone.radiusM) m · \(zone.lat.formatted(.number.precision(.fractionLength(3)))), \(zone.lon.formatted(.number.precision(.fractionLength(3))))")
                                        .font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Button(role: .destructive) { Task { await remove(zone) } } label: {
                                    Image(systemName: "trash").font(.system(size: 15))
                                }
                                .accessibilityLabel("Borrar zona \(index + 1)")
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Zonas privadas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        zones = (try? await api.privacyZones()) ?? []
        // El mapa empieza en una zona ya guardada o donde empezó tu última salida
        if let first = zones.first {
            startCenter = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        } else if let box = library.activities.compactMap(\.bbox).first {
            startCenter = CLLocationCoordinate2D(latitude: (box.minLat + box.maxLat) / 2, longitude: (box.minLon + box.maxLon) / 2)
        } else {
            startCenter = center
        }
        center = startCenter ?? center
    }

    private func add() async {
        saving = true
        defer { saving = false }
        do {
            let zone = try await api.addPrivacyZone(lat: center.latitude, lon: center.longitude, radiusM: Int(radius))
            withAnimation { zones.append(zone) }
            errorMessage = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ zone: PrivacyZone) async {
        if (try? await api.deletePrivacyZone(id: zone.id)) != nil {
            withAnimation { zones.removeAll { $0.id == zone.id } }
        }
    }
}

/// Mapa satélite plano para colocar las zonas: dibuja los círculos guardados y el pendiente en el
/// centro, y devuelve el centro al mover el mapa.
private struct PrivacyZonesMap: UIViewRepresentable {
    var start: CLLocationCoordinate2D
    var zones: [PrivacyZone]
    var pendingRadius: Double
    @Binding var center: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator(center: $center) }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero, mapInitOptions: MapInitOptions(cameraOptions: CameraOptions(center: start, zoom: 14)))
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.rotateEnabled = false
        mapView.mapboxMap.loadStyle(.standardSatellite) { _ in
            MainActor.assumeIsolated { context.coordinator.styleLoaded(on: mapView) }
        }
        context.coordinator.observe(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.center = $center
        context.coordinator.draw(zones: zones, pendingRadius: pendingRadius, on: mapView)
    }

    @MainActor
    final class Coordinator {
        var center: Binding<CLLocationCoordinate2D>
        private var ready = false
        private var zones: [PrivacyZone] = []
        private var pendingRadius: Double = 500
        private var cancelables: [AnyCancelable] = []

        init(center: Binding<CLLocationCoordinate2D>) { self.center = center }

        func observe(_ mapView: MapView) {
            cancelables.append(mapView.mapboxMap.onCameraChanged.observe { [weak self, weak mapView] _ in
                MainActor.assumeIsolated {
                    guard let self, let mapView else { return }
                    self.center.wrappedValue = mapView.mapboxMap.cameraState.center
                    self.drawPending(on: mapView)
                }
            })
        }

        func styleLoaded(on mapView: MapView) {
            let map = mapView.mapboxMap!
            for (key, value) in ["showPointOfInterestLabels": false, "showTransitLabels": false] as [String: Any] {
                try? map.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
            }
            for id in ["zones", "pending"] {
                var source = GeoJSONSource(id: id)
                source.data = .featureCollection(FeatureCollection(features: []))
                try? map.addSource(source)
            }
            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            var fill = FillLayer(id: "zones-fill", source: "zones")
            fill.fillColor = .constant(StyleColor(accent.withAlphaComponent(0.28)))
            fill.fillEmissiveStrength = .constant(1)
            try? map.addLayer(fill)
            var line = LineLayer(id: "zones-line", source: "zones")
            line.lineColor = .constant(StyleColor(accent))
            line.lineWidth = .constant(2)
            line.lineEmissiveStrength = .constant(1)
            try? map.addLayer(line)
            var pending = LineLayer(id: "pending-line", source: "pending")
            pending.lineColor = .constant(StyleColor(.white))
            pending.lineWidth = .constant(2)
            pending.lineDasharray = .constant([2, 2])
            pending.lineEmissiveStrength = .constant(1)
            try? map.addLayer(pending)
            ready = true
            draw(zones: zones, pendingRadius: pendingRadius, on: mapView)
        }

        func draw(zones: [PrivacyZone], pendingRadius: Double, on mapView: MapView) {
            self.zones = zones
            self.pendingRadius = pendingRadius
            guard ready, let map = mapView.mapboxMap else { return }
            let features = zones.map { Feature(geometry: .polygon(Self.circle(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), radius: Double($0.radiusM)))) }
            map.updateGeoJSONSource(withId: "zones", data: .featureCollection(FeatureCollection(features: features)))
            drawPending(on: mapView)
        }

        func drawPending(on mapView: MapView) {
            guard ready, let map = mapView.mapboxMap else { return }
            let ring = Self.circle(map.cameraState.center, radius: pendingRadius)
            map.updateGeoJSONSource(withId: "pending", data: .feature(Feature(geometry: .polygon(ring))))
        }

        /// Círculo de `radius` metros como polígono de 64 lados.
        static func circle(_ c: CLLocationCoordinate2D, radius: Double) -> Polygon {
            let dLat = radius / 110_574
            let dLon = radius / (111_320 * max(cos(c.latitude * .pi / 180), 0.01))
            let ring = (0...64).map { i -> CLLocationCoordinate2D in
                let a = Double(i) / 64 * 2 * .pi
                return CLLocationCoordinate2D(latitude: c.latitude + dLat * sin(a), longitude: c.longitude + dLon * cos(a))
            }
            return Polygon([ring])
        }
    }
}
