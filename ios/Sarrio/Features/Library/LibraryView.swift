import SarrioKit
import SwiftUI
import UniformTypeIdentifiers

/// Biblioteca de cumbres. De momento: importar un GPX y ver qué picos detecta.
struct LibraryView: View {
    @Environment(\.peakPackStore) private var peakPackStore
    @State private var importing = false
    @State private var isProcessing = false
    @State private var lastImport: ImportResult?
    @State private var errorMessage: String?

    struct ImportResult {
        var name: String
        var date: Date?
        var distanceKm: Double
        var elevationGain: Double
        var summits: [DetectedSummit]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if isProcessing {
                    Card { HStack { ProgressView(); Text("Buscando cumbres…").foregroundStyle(Theme.Colors.textSecondary) } }
                }
                if let result = lastImport {
                    importCard(result)
                } else if !isProcessing {
                    EmptyStateView(
                        icon: "mountain.2",
                        title: "Tu biblioteca está vacía",
                        message: "Importa una actividad GPX y detectaremos las cumbres que subiste.",
                        actionTitle: "Importar GPX",
                        action: { importing = true }
                    )
                    .padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Cumbres")
        .toolbar {
            Button { importing = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Importar actividad")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml]) { result in
            Task { await handleImport(result) }
        }
        .alert("No se pudo importar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importCard(_ result: ImportResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let date = result.date {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            StatRow(stats: [
                ("Distancia", result.distanceKm.formatted(.number.precision(.fractionLength(1))), "km"),
                ("Desnivel", result.elevationGain.groupedInteger, "m"),
                ("Cumbres", "\(result.summits.count)", nil),
            ])
            .padding(.vertical, Theme.Spacing.s)

            if result.summits.isEmpty {
                Text("No hemos detectado ninguna cumbre en esta actividad.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Divider()
                ForEach(result.summits, id: \.peak.id) { summit in
                    SummitRow(summit: summit)
                }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let track = try TrackImporter.parse(fileAt: try result.get())
            let summits = try await peakPackStore.detectSummits(in: track.points)
            lastImport = ImportResult(
                name: track.name ?? "Actividad",
                date: track.startDate,
                distanceKm: track.distance / 1000,
                elevationGain: track.elevationGain(),
                summits: summits
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SummitRow: View {
    var summit: DetectedSummit

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(summit.peak.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let time = summit.closestPoint.time {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            if let ele = summit.peak.ele {
                Text("\(ele.groupedInteger) m")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(.vertical, 2)
    }
}
