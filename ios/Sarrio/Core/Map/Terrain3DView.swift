import MapKit
import SarrioKit
import SwiftUI

/// Relieve 3D real (satélite de Apple con elevación) con la ruta y las cumbres encima.
///
/// - `orbit`: la cámara gira despacio alrededor del centro, como un dron; se detiene al tocar el mapa.
/// - `interactive`: permite girar, inclinar y hacer zoom con los dedos.
/// La Fase 4 lo sustituirá por el vuelo de cámara con Mapbox sobre la ruta completa.
struct Terrain3DView: View {
    var center: CLLocationCoordinate2D
    var distance: CLLocationDistance = 2_800
    var segments: [[CLLocationCoordinate2D]] = []
    var summits: [PeakRef] = []
    var orbit = true
    var interactive = true

    @State private var position: MapCameraPosition = .automatic
    @State private var heading: CLLocationDirection = 20
    @State private var userTookOver = false
    @State private var orbitTask: Task<Void, Never>?

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: segment)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(summits) { peak in
                Annotation(peak.displayName, coordinate: CLLocationCoordinate2D(latitude: peak.lat, longitude: peak.lon), anchor: .bottom) {
                    SummitPin()
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {
            MapCompass().mapControlVisibility(interactive ? .automatic : .hidden)
            MapPitchToggle().mapControlVisibility(interactive ? .automatic : .hidden)
        }
        .onAppear {
            position = .camera(camera(heading: heading))
            startOrbit()
        }
        .onDisappear { orbitTask?.cancel() }
        .onMapCameraChange(frequency: .onEnd) { context in
            // Si el usuario mueve el mapa, la órbita se para y no vuelve a recolocar la cámara.
            if interactive, abs(context.camera.heading - heading) > 2 || abs(context.camera.distance - distance) > 50 {
                userTookOver = true
                orbitTask?.cancel()
            }
        }
    }

    private func camera(heading: CLLocationDirection) -> MapCamera {
        MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 68)
    }

    private func startOrbit() {
        guard orbit else { return }
        orbitTask?.cancel()
        orbitTask = Task { @MainActor in
            while !Task.isCancelled, !userTookOver {
                heading = (heading + 12).truncatingRemainder(dividingBy: 360)
                withAnimation(.linear(duration: 4)) { position = .camera(camera(heading: heading)) }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// Marcador de cumbre: triángulo de acento sobre una base blanca que flota con sombra.
struct SummitPin: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.accent, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .elevation(.medium)
            Rectangle().fill(.white).frame(width: 2, height: 10)
        }
    }
}

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension PeakRef {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
