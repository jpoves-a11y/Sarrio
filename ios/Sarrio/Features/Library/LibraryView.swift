import SarrioKit
import SwiftUI
import UniformTypeIdentifiers

/// Biblioteca de cumbres. De momento permite importar un GPX y ver qué picos detecta.
struct LibraryView: View {
    @Environment(\.peakPackStore) private var peakPackStore
    @State private var importing = false
    @State private var lastImport: ImportResult?
    @State private var error: String?

    struct ImportResult {
        var name: String
        var distanceKm: Double
        var elevationGain: Double
        var summits: [DetectedSummit]
    }

    var body: some View {
        List {
            if let result = lastImport {
                Section("Última importación: \(result.name)") {
                    LabeledContent("Distancia", value: "\(result.distanceKm.formatted(.number.precision(.fractionLength(1)))) km")
                    LabeledContent("Desnivel +", value: "\(Int(result.elevationGain)) m")
                    if result.summits.isEmpty {
                        Text("No se ha detectado ninguna cumbre").foregroundStyle(.secondary)
                    }
                    ForEach(result.summits, id: \.peak.id) { summit in
                        Label {
                            VStack(alignment: .leading) {
                                Text(summit.peak.displayName).font(.headline)
                                if let ele = summit.peak.ele { Text("\(Int(ele)) m").foregroundStyle(.secondary) }
                            }
                        } icon: {
                            Image(systemName: "flag.fill").foregroundStyle(.tint)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Aún no hay cumbres",
                    systemImage: "mountain.2",
                    description: Text("Importa un GPX o conecta Apple Health para empezar tu biblioteca.")
                )
            }
        }
        .navigationTitle("Mis cumbres")
        .toolbar {
            Button("Importar", systemImage: "square.and.arrow.down") { importing = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml]) { result in
            Task { await handleImport(result) }
        }
        .alert("No se pudo importar", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("OK") { error = nil }
        } message: { Text($0) }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        do {
            let track = try TrackImporter.parse(fileAt: try result.get())
            let summits = try await peakPackStore.detectSummits(in: track.points)
            lastImport = ImportResult(
                name: track.name ?? "Actividad",
                distanceKm: track.distance / 1000,
                elevationGain: track.elevationGain(),
                summits: summits
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
