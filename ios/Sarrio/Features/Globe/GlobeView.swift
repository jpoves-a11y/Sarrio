import SarrioKit
import SwiftUI

struct GlobeView: View {
    /// Fase 4: cumbres del usuario (y de sus amigos) desde la API / caché local.
    @State private var peaks: [Peak] = []

    var body: some View {
        GlobeMapView(peaks: peaks)
    }
}
