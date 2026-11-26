import SarrioKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx")
    static let fit = UTType(importedAs: "com.garmin.fit")
    static let tcx = UTType(importedAs: "com.garmin.tcx")
}

/// Biblioteca de cumbres: la cima más alta en 3D, los picos subidos y las actividades recientes.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var importing = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.l) {
                if let progress = store.syncProgress {
                    SyncStatusCard(progress: progress)
                        .padding(.top, Theme.Spacing.s)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let library = store.library, !library.ascents.isEmpty {
                    if let highest = library.summary.highestPeak {
                        SummitHero(peak: highest, summary: library.summary, elevationGain: store.totalElevationGain)
                            .staggeredAppear(0)
                    }
                    if !store.healthConnected && HealthKitService.isAvailable {
                        HealthConnectCard { Task { await store.connectHealth() } }.staggeredAppear(1)
                    }
                    if store.polarAvailable && !store.polarConnected {
                        PolarConnectCard { Task { await store.connectPolar() } }.staggeredAppear(1)
                    }
                    peaksSection.staggeredAppear(2)
                    if !summitedActivities.isEmpty { activitiesSection.staggeredAppear(3) }
                } else if store.isLoading && store.library == nil {
                    ProgressView().padding(.top, 120)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Cumbres")
        .safeAreaInset(edge: .bottom) {
            // Las sincronizaciones tienen su tarjeta de progreso arriba; la píldora queda para los archivos
            if store.isImporting {
                ProgressPill(text: "Buscando cumbres…")
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: store.isImporting)
        .toolbar {
            Menu {
                Button { importing = true } label: { Label("Importar archivo (GPX, FIT, TCX)", systemImage: "doc.badge.plus") }
                if store.healthConnected {
                    Button { Task { await store.syncHealth() } } label: { Label("Sincronizar Apple Health", systemImage: "arrow.triangle.2.circlepath") }
                }
                if store.polarConnected {
                    Button { Task { await store.syncPolar() } } label: { Label("Traer entrenos de Polar", systemImage: "dot.radiowaves.left.and.right") }
                } else if store.polarAvailable {
                    Button { Task { await store.connectPolar() } } label: { Label("Conectar Polar", systemImage: "dot.radiowaves.left.and.right") }
                }
            } label: {
                Image(systemName: "plus").fontWeight(.semibold)
            }
            .accessibilityLabel("Añadir actividad")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gpx, .fit, .tcx, .xml], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { Task { await store.importFile(at: url) } }
        }
        .sheet(item: $store.lastImport) { outcome in
            ImportResultView(outcome: outcome)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.hero)
        }
        .alert("Algo no ha ido bien", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: Secciones

    private var peaksSection: some View {
        @Bindable var store = store
        return VStack(spacing: Theme.Spacing.s) {
            HStack {
                SectionHeader(title: "Tus picos")
                Menu {
                    Picker("Orden", selection: $store.sortOrder) {
                        ForEach(LibraryStore.SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(store.sortOrder.title, systemImage: "arrow.up.arrow.down")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            ForEach(store.peakGroups) { group in
                NavigationLink { PeakDetailView(group: group) } label: { PeakCard(group: group) }
                    .buttonStyle(.pressableCard)
                    .scrollDepth()
            }
        }
        .animation(Theme.Motion.spring, value: store.sortOrder)
    }

    /// En Cumbres, solo las actividades en las que coronaste alguna cima (todas están en Perfil).
    private var summitedActivities: [Activity] { store.activities.filter { !($0.ascents ?? []).isEmpty } }

    private var activitiesSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                SectionHeader(title: "Actividades con cima")
                NavigationLink { MountainActivitiesView() } label: {
                    Text("Ver todas").font(.sarrio(14, .semibold)).foregroundStyle(Theme.Colors.accent)
                }
            }
            ForEach(summitedActivities.prefix(10)) { activity in
                NavigationLink { ActivityDetailView(activity: activity) } label: { ActivityRow(activity: activity) }
                    .buttonStyle(.pressableCard)
                    .scrollDepth()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            if store.syncProgress == nil {
            EmptyStateView(
                icon: "mountain.2",
                title: "Tu biblioteca de cumbres",
                message: "Conecta Apple Health o importa un GPX, FIT o TCX y detectaremos las cimas que has pisado."
            )
            .padding(.top, Theme.Spacing.l)
            }
            if HealthKitService.isAvailable && !store.healthConnected {
                HealthConnectCard { Task { await store.connectHealth() } }
            }
            if store.polarAvailable && !store.polarConnected {
                PolarConnectCard { Task { await store.connectPolar() } }
            }
            Button { importing = true } label: { Label("Importar archivo", systemImage: "doc.badge.plus") }
                .buttonStyle(.secondary)
        }
    }
}

// MARK: - Héroe 3D

/// La cima más alta del usuario en relieve 3D, girando despacio, con las cifras grandes encima.
private struct SummitHero: View {
    var peak: PeakRef
    var summary: Library.Summary
    var elevationGain: Double

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Terrain3DView(center: peak.coordinate, distance: 3_200, summits: [peak], orbit: true, interactive: false)
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TU CIMA MÁS ALTA")
                        .font(.statLabel).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(peak.displayName)
                            .font(.sarrio(26, .semibold))
                            .foregroundStyle(.white)
                        if let ele = peak.ele {
                            Text("\(ele.groupedInteger) m")
                                .font(.sarrio(15, .bold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                HStack(spacing: 0) {
                    HeroStat(label: "Picos", value: "\(summary.uniquePeaks)")
                    HeroStat(label: "Ascensiones", value: "\(summary.ascents)")
                    HeroStat(label: "Desnivel", value: elevationGain.groupedInteger, unit: "m")
                }
                .padding(Theme.Spacing.m)
                .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .environment(\.colorScheme, .dark)
            }
            .padding(Theme.Spacing.m)
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .elevation(.high)
        .interactiveTilt(maxAngle: 6)
        .frame(height: 400)
        .padding(.top, Theme.Spacing.s)
    }
}

private struct HeroStat: View {
    var label: String
    var value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.statLabel).tracking(0.6).foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.statValue).foregroundStyle(.white)
                if let unit { Text(unit).font(.statUnit).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tarjetas

private struct PeakCard: View {
    var group: PeakGroup

    var body: some View {
        Card(elevation: .low) {
            HStack(spacing: Theme.Spacing.m) {
                PeakBadge(count: group.ascents.count)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.peak.displayName)
                        .font(.sarrio(17, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.sarrio(13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                if let ele = group.peak.ele {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(ele.groupedInteger).font(.sarrio(20, .bold).monospacedDigit())
                        Text("m").font(.statUnit).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
    }

    private var subtitle: String {
        let last = group.lastAscent.formatted(date: .abbreviated, time: .omitted)
        return group.ascents.count == 1 ? last : "\(group.ascents.count) veces · última \(last)"
    }
}

/// Insignia del pico: un triángulo con volumen (degradado y luz) y el número de ascensiones.
struct PeakBadge: View {
    var count: Int
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [Theme.Colors.accent.opacity(0.18), Theme.Colors.accent.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "mountain.2.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.7)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.Colors.accent.opacity(0.3), radius: 3, y: 2)
            if count > 1 {
                Text("\(count)")
                    .font(.sarrio(11, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.Colors.accent, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                    .offset(x: size * 0.36, y: -size * 0.36)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ActivityRow: View {
    var activity: Activity

    var body: some View {
        Card(elevation: .low) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.displayTitle)
                        .font(.sarrio(16, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(activity.sport.title) · \(activity.startAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.sarrio(13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: activity.visibility.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            StatRow(stats: [
                ("Distancia", ((activity.distanceM ?? 0) / 1000).formatted(.number.precision(.fractionLength(1))), "km"),
                ("Desnivel", (activity.elevGainM ?? 0).groupedInteger, "m"),
                ("Cumbres", "\(activity.ascents?.count ?? 0)", nil),
            ])
            .padding(.top, Theme.Spacing.xs)
        }
    }
}

private struct HealthConnectCard: View {
    var action: () -> Void

    var body: some View {
        Card(elevation: .medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color(red: 1, green: 0.38, blue: 0.45), Color(red: 0.96, green: 0.2, blue: 0.33)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .elevation(.low)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conecta Apple Health")
                        .font(.sarrio(17, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Leemos tus entrenos con GPS, también los de tu Apple Watch, y añadimos solas las cumbres nuevas.")
                        .font(.sarrio(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Button("Conectar", action: action).buttonStyle(.primary).padding(.top, Theme.Spacing.xs)
        }
    }
}

private struct PolarConnectCard: View {
    var action: () -> Void

    var body: some View {
        Card(elevation: .medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color(red: 0.86, green: 0.1, blue: 0.2), Color(red: 0.7, green: 0.05, blue: 0.14)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .elevation(.low)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conecta Polar")
                        .font(.sarrio(17, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Traemos los entrenos con GPS que subas a Polar Flow a partir de ahora y buscamos sus cumbres. Los anteriores, expórtalos desde Flow e impórtalos con +.")
                        .font(.sarrio(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Button("Conectar con Polar", action: action).buttonStyle(.primary).padding(.top, Theme.Spacing.xs)
        }
    }
}

/// Sincronización en vivo: qué fuente, cuántos entrenos ha encontrado (y de qué deportes), cuál
/// procesa ahora, cuánto falta y cuántas cumbres nuevas lleva.
private struct SyncStatusCard: View {
    var progress: SyncProgress

    var body: some View {
        Card(elevation: .medium) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle().fill(Theme.Colors.accent.opacity(0.12)).frame(width: 40, height: 40)
                    if progress.phase == .done {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.Colors.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: progress.source.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                            .symbolEffect(.pulse, isActive: true)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sarrio(16, .bold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle).font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if progress.total > 0 {
                    Text("\(progress.processed)/\(progress.total)")
                        .font(.sarrio(15, .bold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            if progress.phase == .searching {
                ProgressView().progressViewStyle(.linear).tint(Theme.Colors.accent)
            } else if progress.total > 0 {
                ProgressView(value: progress.fraction).progressViewStyle(.linear).tint(Theme.Colors.accent)
                    .animation(.easeOut(duration: 0.4), value: progress.fraction)
            }
            if !progress.sportsSummary.isEmpty || progress.newSummits > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if progress.newSummits > 0 {
                            chip("\(progress.newSummits) cumbres nuevas", icon: "mountain.2.fill", accent: true)
                        }
                        ForEach(progress.sportsSummary.prefix(4).map { $0.sport }, id: \.self) { sport in
                            chip("\(progress.bySport[sport] ?? 0) \(sport.title.lowercased())", icon: nil, accent: false)
                        }
                    }
                }
            }
        }
        .animation(Theme.Motion.spring, value: progress.phase)
    }

    private var title: String {
        switch progress.phase {
        case .searching: "Buscando entrenos en \(progress.source.title)…"
        case .processing: "Sincronizando \(progress.source.title)"
        case .done:
            progress.total == 0 ? "\(progress.source.title) al día" : "\(progress.source.title) sincronizado"
        }
    }

    private var subtitle: String {
        switch progress.phase {
        case .searching: return "Un momento"
        case .processing:
            let now = progress.current.map { "Procesando \($0)" } ?? "Procesando"
            guard let remaining = progress.remaining else { return now }
            return now + " · \(Self.duration(remaining))"
        case .done:
            if progress.total == 0 {
                // Polar solo entrega lo subido a Flow después de conectar Sarrio
                return progress.source == .polar
                    ? "Nada nuevo. Polar solo envía lo subido a Flow tras conectar Sarrio"
                    : "No hay entrenos nuevos con GPS"
            }
            return "\(progress.newActivities) actividades nuevas de \(progress.total) entrenos"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "menos de 1 min" }
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "≈ \(minutes) min" : "≈ \(minutes / 60) h \(minutes % 60) min"
    }

    private func chip(_ text: String, icon: String?, accent: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.sarrio(12, .semibold))
        }
        .foregroundStyle(accent ? .white : Theme.Colors.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(accent ? AnyShapeStyle(Theme.Colors.accent) : AnyShapeStyle(Theme.Colors.groupedBackground), in: Capsule())
    }
}

private struct ProgressPill: View {
    var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView().controlSize(.small)
            Text(text).font(.sarrio(14, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .elevation(.medium)
    }
}
