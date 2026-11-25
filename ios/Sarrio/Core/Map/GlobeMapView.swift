import MapboxMaps
import SarrioKit
import SwiftUI

/// Globo satélite con las cumbres como puntos. Los estilos v12 de Mapbox usan proyección globo
/// a zoom bajo; al acercarse pasa a Mercator automáticamente.
/// Fase 4: agrupación (clustering), selección de cumbre y vuelo de cámara.
struct GlobeMapView: View {
    var peaks: [Peak]

    var body: some View {
        Map(initialViewport: .camera(center: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), zoom: 1.4)) {
            CircleAnnotationGroup(peaks, id: \.id) { peak in
                CircleAnnotation(centerCoordinate: CLLocationCoordinate2D(latitude: peak.lat, longitude: peak.lon))
                    .circleColor(StyleColor(UIColor.systemOrange))
                    .circleRadius(6)
                    .circleStrokeColor(StyleColor(UIColor.white))
                    .circleStrokeWidth(1.5)
            }
        }
        .mapStyle(.satelliteStreets)
        .ignoresSafeArea(edges: .top)
    }
}
