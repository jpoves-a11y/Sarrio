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
                if let library = store.library, !library.ascents.isEmpty {
                    if let highest = library.summary.highestPeak {
                        SummitHero(peak: highest, summary: library.summary, elevationGain: store.totalElevationGain)
                            .staggeredAppear(0)
                    }
                    if !store.healthConnected && HealthKitService.isAvailable {
                        HealthConnectCard { Task { await store.connectHealth() } }.staggeredAppear(1)
                    }
                    peaksSection.staggeredAppear(2)
                    if !store.activities.isEmpty { activitiesSection.staggeredAppear(3) }
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
            if store.isImporting || store.isSyncingHealth {
                ProgressPill(text: store.isImporting ? "Buscando cumbres…" : "Sincronizando Apple Health…")
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: store.isImporting || store.isSyncingHealth)
        .toolbar {
            Menu {
                Button { importing = true } label: { Label("Importar archivo (GPX, FIT, TCX)", systemImage: "doc.badge.plus") }
                if store.healthConnected {
                    Button { Task { await store.syncHealth() } } label: { Label("Sincronizar Apple Health", systemImage: "arrow.triangle.2.circlepath") }
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
                        .font(.system(size: 14, weight: .semibold))
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

    private var activitiesSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            SectionHeader(title: "Actividades")
            ForEach(store.activities.prefix(10)) { activity in
                NavigationLink { ActivityDetailView(activity: activity) } label: { ActivityRow(activity: activity) }
                    .buttonStyle(.pressableCard)
                    .scrollDepth()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(
                icon: "mountain.2",
                title: "Tu biblioteca de cumbres",
                message: "Conecta Apple Health o importa un GPX, FIT o TCX y detectaremos las cimas que has pisado."
            )
            .padding(.top, Theme.Spacing.l)
            if HealthKitService.isAvailable && !store.healthConnected {
                HealthConnectCard { Task { await store.connectHealth() } }
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
                    Text(peak.displayName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    if let ele = peak.ele {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(ele.groupedInteger).font(.heroValue).foregroundStyle(.white)
                            Text("m").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                        }
                        .contentTransition(.numericText())
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                if let ele = group.peak.ele {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(ele.groupedInteger).font(.system(size: 20, weight: .bold).monospacedDigit())
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
                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(activity.sport.title) · \(activity.startAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 13))
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Leemos tus entrenos con GPS, también los de tu Apple Watch, y añadimos solas las cumbres nuevas.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Button("Conectar", action: action).buttonStyle(.primary).padding(.top, Theme.Spacing.xs)
        }
    }
}

private struct ProgressPill: View {
    var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .elevation(.medium)
    }
}
