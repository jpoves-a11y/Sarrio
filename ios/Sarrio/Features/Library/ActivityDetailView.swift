import SarrioKit
import SwiftUI

/// Detalle de una actividad: cifras, cimas alcanzadas y perfil de elevación. El mapa 3D (el replay)
/// se abre a pantalla completa con «Ver en el mapa 3D», así la ficha abre al instante.
struct ActivityDetailView: View {
    var activity: Activity
    @Environment(\.apiClient) private var api
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ActivityDetail?
    @State private var plan: ReplayPlan?
    @State private var visibility: Visibility
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var showsMap = false

    init(activity: Activity) {
        self.activity = activity
        _visibility = State(initialValue: activity.visibility)
    }

    private var ascents: [Ascent] {
        (detail?.ascents ?? activity.ascents ?? []).sorted { $0.summitedAt < $1.summitedAt }
    }

    private var endDate: Date? { activity.durationS.map { activity.startAt.addingTimeInterval($0) } }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header.staggeredAppear(0)
                statsCard.staggeredAppear(1)
                mapButton.staggeredAppear(2)
                summitsCard.staggeredAppear(3)
                if let plan, plan.elevations.contains(where: { $0 != nil }) {
                    profileCard(plan).staggeredAppear(4)
                }
                settingsCard.staggeredAppear(5)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.groupedBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $showsMap) {
            if let detail {
                ZStack(alignment: .topTrailing) {
                    ActivityReplayView(
                        activityId: activity.id,
                        segments: detail.segments,
                        summits: ascents.map(\.peak),
                        start: activity.startAt,
                        end: endDate,
                        height: nil
                    )
                    .ignoresSafeArea()
                    Button { showsMap = false } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, 56)
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

    // MARK: Secciones

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            SportBadge(sport: activity.sport, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.sport.title.uppercased())
                    .font(.statLabel).tracking(1.2)
                    .foregroundStyle(Theme.Colors.accent)
                Text(activity.displayTitle)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(activity.startAt.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Label(sourceTitle, systemImage: sourceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
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
            Divider().padding(.vertical, Theme.Spacing.xs)
            StatRow(stats: [
                ("Cimas", "\(ascents.count)", nil),
                ("Máx.", maxElevation.map(\.groupedInteger) ?? "–", maxElevation == nil ? nil : "m"),
                ("Ritmo", pace, nil),
            ])
        }
    }

    /// Botón grande que abre el replay 3D: la promesa del mapa, con profundidad.
    private var mapButton: some View {
        Button { showsMap = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "view.3d")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ver en el mapa 3D").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    Text(detail == nil ? "Cargando la ruta…" : "Vuela la ruta sobre el relieve")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if detail == nil {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Theme.Spacing.m)
            .background(
                LinearGradient(colors: [Theme.Colors.accent.opacity(0.88), Theme.Colors.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .elevation(.high)
        }
        .buttonStyle(.pressableCard)
        .disabled(detail == nil || detail?.segments.isEmpty == true)
    }

    private var summitsCard: some View {
        Card(elevation: .medium) {
            HStack {
                SectionHeader(title: "Cimas alcanzadas")
                Text("\(ascents.count)")
                    .font(.system(size: 17, weight: .heavy).monospacedDigit())
                    .foregroundStyle(ascents.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.accent)
            }
            if ascents.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "flag.slash").foregroundStyle(Theme.Colors.textSecondary)
                    Text(detail == nil ? "Comprobando…" : "Ninguna cima en esta ruta")
                        .font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(ascents) { ascent in
                    HStack(spacing: Theme.Spacing.m) {
                        PeakBadge(count: 1, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ascent.peak.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            Text([ascent.peak.range, ascent.summitedAt.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
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
    }

    private func profileCard(_ plan: ReplayPlan) -> some View {
        Card(elevation: .low) {
            SectionHeader(title: "Perfil")
            ElevationProfileView(plan: plan, fraction: 1, baseColor: Theme.Colors.separator, showsMarker: false)
                .frame(height: 90)
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

    // MARK: Cifras

    private var duration: String {
        guard let s = activity.durationS, s > 0 else { return "–" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(m)" : "\(m) min"
    }

    /// min/km (en montaña orienta más que la velocidad).
    private var pace: String {
        guard let s = activity.durationS, let d = activity.distanceM, d > 100, s > 0 else { return "–" }
        let perKm = s / (d / 1000)
        return String(format: "%d:%02d", Int(perKm) / 60, Int(perKm) % 60)
    }

    private var maxElevation: Double? {
        plan?.elevations.compactMap { $0 }.max() ?? ascents.compactMap(\.peak.ele).max()
    }

    private var sourceTitle: String {
        switch activity.source {
        case "healthkit": "Apple Health"
        case "polar": "Polar"
        case "file": "Archivo importado"
        default: "Sarrio"
        }
    }

    private var sourceIcon: String {
        switch activity.source {
        case "healthkit": "heart.fill"
        case "polar": "dot.radiowaves.left.and.right"
        case "file": "doc"
        default: "mountain.2"
        }
    }

    private func load() async {
        do {
            let loaded = try await api.activity(id: activity.id)
            let points = loaded.segments.flatMap { $0 }
            let built = ReplayPlan(track: points, summits: loaded.ascents.map { GeoPoint(lat: $0.peak.lat, lon: $0.peak.lon) })
            withAnimation(Theme.Motion.spring) {
                detail = loaded
                plan = built
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Icono del deporte con volumen: degradado de acento y sombra.
struct SportBadge: View {
    var sport: SportType
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: sport.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Theme.Colors.accent.opacity(0.85), Theme.Colors.accent], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .elevation(.low)
    }
}

extension SportType {
    /// SF Symbol del deporte.
    var symbol: String {
        switch self {
        case .hiking: "figure.hiking"
        case .mountaineering: "mountain.2.fill"
        case .trailRunning, .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .backcountrySkiing: "figure.skiing.crosscountry"
        case .skiing: "figure.skiing.downhill"
        case .snowshoeing: "snowflake"
        case .climbing: "figure.climbing"
        case .other: "figure.mixed.cardio"
        }
    }
}
