import CoreLocation
import SarrioKit
import SwiftUI

/// Detalle de una actividad: cifras, cimas alcanzadas y perfil de elevación. El mapa 3D (el replay)
/// se abre a pantalla completa con «Ver en el mapa 3D», así la ficha abre al instante.
struct ActivityDetailView: View {
    var activity: Activity
    @Environment(\.apiClient) private var api
    @Environment(LibraryStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ActivityDetail?
    @State private var plan: ReplayPlan?
    @State private var analysis: ActivityAnalysis?
    @State private var profileFraction: Double?
    @State private var visibility: Visibility
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var showsMap = false
    /// Cumbre abierta en 3D (con la ruta encima).
    @State private var summitInMap: Ascent?

    init(activity: Activity) {
        self.activity = activity
        _visibility = State(initialValue: activity.visibility)
    }

    private var ascents: [Ascent] {
        (detail?.ascents ?? activity.ascents ?? []).sorted { $0.summitedAt < $1.summitedAt }
    }

    /// Si alguna cima de esta salida ya la habías subido en otras: tu tiempo hasta la cumbre en cada vez.
    private var summitHistory: (peak: PeakRef, entries: [(date: Date, seconds: Double, current: Bool)])? {
        guard activity.userId == session.me?.id else { return nil }
        let starts = Dictionary(store.activities.map { ($0.id, $0.startAt) }, uniquingKeysWith: { a, _ in a })
        for ascent in ascents {
            let all = (store.library?.ascents ?? []).filter { $0.peak.id == ascent.peak.id }
            let entries = all.compactMap { a -> (date: Date, seconds: Double, current: Bool)? in
                guard let id = a.activityId, let start = id == activity.id ? activity.startAt : starts[id] else { return nil }
                let s = a.summitedAt.timeIntervalSince(start)
                return s > 60 ? (date: a.summitedAt, seconds: s, current: id == activity.id) : nil
            }
            .sorted { $0.date < $1.date }
            if entries.count >= 2, entries.contains(where: \.current) { return (ascent.peak, entries) }
        }
        return nil
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
                if let analysis, !analysis.slopes.isEmpty {
                    ActivityAnalysisSection(analysis: analysis).staggeredAppear(5)
                }
                if let center = plan?.center, let end = endDate {
                    ActivityWeatherSection(
                        activityId: activity.id,
                        center: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon),
                        start: activity.startAt,
                        end: end,
                        summit: ascents.max { ($0.peak.ele ?? 0) < ($1.peak.ele ?? 0) }.map { (name: $0.peak.displayName, at: $0.summitedAt) }
                    )
                    .staggeredAppear(6)
                }
                if let history = summitHistory {
                    SummitHistory(peak: history.peak, entries: history.entries).staggeredAppear(6)
                }
                // Editar y borrar, solo en las mías (las de amigos llegan desde el feed)
                if activity.userId == session.me?.id { settingsCard.staggeredAppear(7) }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.page)
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
                    // Cerrar, dentro de la zona segura a la altura de los contadores
                    Button { showsMap = false } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .environment(\.colorScheme, .dark)
                    }
                    .padding(Theme.Spacing.m)
                }
            }
        }
        .fullScreenCover(item: $summitInMap) { ascent in
            SummitMapView(ascent: ascent, route: (detail?.segments ?? []).map { $0.map(\.coordinate) })
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
                    .font(.sarrio(26, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(activity.startAt.formatted(date: .complete, time: .shortened))
                    .font(.sarrio(14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Label(sourceTitle, systemImage: sourceIcon)
                    .font(.sarrio(12, .semibold))
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
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ver en el mapa 3D").font(.sarrio(18, .bold)).foregroundStyle(.white)
                    Text(detail == nil ? "Cargando la ruta…" : "Vuela la ruta sobre el relieve")
                        .font(.sarrio(13)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if detail == nil {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .elevation(.medium)
        }
        .buttonStyle(.pressableCard)
        .disabled(detail == nil || detail?.segments.isEmpty == true)
    }

    private var summitsCard: some View {
        Card(elevation: .medium) {
            HStack {
                SectionHeader(title: "Cimas alcanzadas")
                Text("\(ascents.count)")
                    .font(.sarrio(17, .semibold).monospacedDigit())
                    .foregroundStyle(ascents.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.accent)
            }
            if ascents.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "flag.slash").foregroundStyle(Theme.Colors.textSecondary)
                    Text(detail == nil ? "Comprobando…" : "Ninguna cima en esta ruta")
                        .font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(ascents) { ascent in
                    HStack(spacing: Theme.Spacing.m) {
                        PeakBadge(count: 1, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ascent.peak.displayName).font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text([ascent.peak.ele.map { "\($0.groupedInteger) m" }, ascent.peak.range,
                                  ascent.summitedAt.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                .font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        // La cumbre en el relieve 3D, con la ruta de esta actividad
                        Button { summitInMap = ascent } label: {
                            Label("Ver en 3D", systemImage: "view.3d")
                                .font(.sarrio(13, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                                .elevation(.low)
                                .fixedSize()
                        }
                        .buttonStyle(.pressableCard)
                        .disabled(detail == nil)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func profileCard(_ plan: ReplayPlan) -> some View {
        Card(elevation: .low) {
            SectionHeader(title: "Perfil")
            // Desliza el dedo por el perfil para ver la altitud, la distancia y el desnivel de cada punto
            ScrubbableProfile(plan: plan, fraction: $profileFraction)
        }
    }

    private var settingsCard: some View {
        Card(elevation: .low) {
            HStack {
                Text("Quién la ve").font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Picker("Quién la ve", selection: $visibility) {
                    ForEach(Visibility.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: visibility) { _, new in Task { await store.update(activity, visibility: new) } }
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Borrar actividad", systemImage: "trash").font(.sarrio(16, .medium))
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
            analysis = ActivityAnalysis(points: points)
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

/// Icono del deporte: el símbolo en línea fina y en el color de acento, sin fondo.
struct SportBadge: View {
    var sport: SportType
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: sport.symbol)
            .font(.system(size: size * 0.5, weight: .light))
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: size, height: size)
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

/// Una cumbre coronada en el relieve 3D, con la ruta de la actividad dibujada y la cámara girando.
/// Limpio: el mapa a pantalla completa y una píldora discreta con el nombre.
private struct SummitMapView: View {
    var ascent: Ascent
    var route: [[CLLocationCoordinate2D]]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Terrain3DView(center: ascent.peak.coordinate, distance: 2_600, segments: route, summits: [ascent.peak],
                          orbit: true, interactive: true)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .environment(\.colorScheme, .dark)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Text(ascent.peak.displayName).font(.sarrio(16, .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Coronada a las \(ascent.summitedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.sarrio(13)).foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .environment(\.colorScheme, .dark)
            }
            .padding(Theme.Spacing.m)
        }
    }
}
