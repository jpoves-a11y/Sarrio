import MapKit
import SarrioKit
import SwiftUI

/// Detalle de una actividad: la ruta sobre relieve 3D, las cifras y las cumbres.
struct ActivityDetailView: View {
    var activity: Activity
    @Environment(\.apiClient) private var api
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ActivityDetail?
    @State private var visibility: Visibility
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var expandedMap = false

    init(activity: Activity) {
        self.activity = activity
        _visibility = State(initialValue: activity.visibility)
    }

    private var segments: [[CLLocationCoordinate2D]] {
        (detail?.segments ?? []).map { $0.map(\.coordinate) }
    }

    private var ascents: [Ascent] { detail?.ascents ?? activity.ascents ?? [] }

    /// Centro de la vista: la cumbre más alta o, si no hay, el centro de la ruta.
    private var focus: CLLocationCoordinate2D? {
        if let top = ascents.max(by: { ($0.peak.ele ?? 0) < ($1.peak.ele ?? 0) }) { return top.peak.coordinate }
        let all = segments.flatMap { $0 }
        guard !all.isEmpty else { return nil }
        return CLLocationCoordinate2D(latitude: all.map(\.latitude).reduce(0, +) / Double(all.count),
                                      longitude: all.map(\.longitude).reduce(0, +) / Double(all.count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                mapHero
                header.staggeredAppear(1)
                statsCard.staggeredAppear(2)
                if !ascents.isEmpty { summitsCard.staggeredAppear(3) }
                settingsCard.staggeredAppear(4)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.groupedBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $expandedMap) {
            if let focus {
                ZStack(alignment: .topTrailing) {
                    Terrain3DView(center: focus, distance: 4_500, segments: segments, summits: ascents.map(\.peak), orbit: false, interactive: true)
                        .ignoresSafeArea()
                    Button { expandedMap = false } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .frame(width: 36, height: 36).background(.regularMaterial, in: Circle()).elevation(.medium)
                    }
                    .padding(Theme.Spacing.m)
                }
            }
        }
        .confirmationDialog("¿Borrar esta actividad?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar actividad y sus cumbres", role: .destructive) {
                Task {
                    await store.delete(activity)
                    dismiss()
                }
            }
        } message: {
            Text("Se borrarán la ruta y las ascensiones que salieron de ella.")
        }
        .alert("No se pudo cargar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var mapHero: some View {
        ZStack(alignment: .bottomTrailing) {
            if let focus, detail != nil {
                Terrain3DView(center: focus, distance: 4_000, segments: segments, summits: ascents.map(\.peak), orbit: true, interactive: false)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Theme.Colors.separator).overlay(ProgressView())
            }
            Button { expandedMap = true } label: {
                Label("Explorar en 3D", systemImage: "view.3d")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .elevation(.medium)
            }
            .padding(Theme.Spacing.m)
            .disabled(focus == nil)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .elevation(.high)
        .padding(.top, Theme.Spacing.s)
        .animation(Theme.Motion.spring, value: detail != nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activity.sport.title.uppercased())
                .font(.statLabel).tracking(1.2)
                .foregroundStyle(Theme.Colors.accent)
            Text(activity.displayTitle)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(activity.startAt.formatted(date: .complete, time: .shortened))
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCard: some View {
        Card(elevation: .medium) {
            StatRow(stats: [
                ("Distancia", ((activity.distanceM ?? 0) / 1000).formatted(.number.precision(.fractionLength(1))), "km"),
                ("Desnivel", (activity.elevGainM ?? 0).groupedInteger, "m"),
                ("Tiempo", duration, nil),
            ])
        }
    }

    private var duration: String {
        guard let s = activity.durationS, s > 0 else { return "–" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(m)" : "\(m) min"
    }

    private var summitsCard: some View {
        Card(elevation: .medium) {
            SectionHeader(title: ascents.count == 1 ? "Cumbre" : "\(ascents.count) cumbres")
            ForEach(ascents.sorted { $0.summitedAt < $1.summitedAt }) { ascent in
                HStack(spacing: Theme.Spacing.m) {
                    PeakBadge(count: 1, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ascent.peak.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Text(ascent.summitedAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if let ele = ascent.peak.ele {
                        Text("\(ele.groupedInteger) m").font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var settingsCard: some View {
        Card(elevation: .low) {
            HStack {
                Text("Quién la ve").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Picker("Quién la ve", selection: $visibility) {
                    ForEach(Visibility.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: visibility) { _, new in Task { await store.update(activity, visibility: new) } }
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Borrar actividad", systemImage: "trash").font(.system(size: 16, weight: .medium))
            }
        }
    }

    private func load() async {
        do {
            let loaded = try await api.activity(id: activity.id)
            withAnimation(Theme.Motion.spring) { detail = loaded }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
