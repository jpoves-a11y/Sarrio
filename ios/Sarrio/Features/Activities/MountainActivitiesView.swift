import Combine
import Observation
import SarrioKit
import SwiftUI

/// Actividades de montaña (senderismo, trail, montañismo…) de cualquier fuente, tengan cimas o no.
@MainActor
@Observable
final class MountainActivitiesStore {
    enum Filter: String, CaseIterable, Identifiable {
        case all, hiking, trail, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Todas"
            case .hiking: "Senderismo"
            case .trail: "Trail"
            case .other: "Otras"
            }
        }

        func matches(_ sport: SportType) -> Bool {
            switch self {
            case .all: sport.isMountain
            case .hiking: sport == .hiking
            case .trail: sport == .trailRunning
            case .other: sport.isMountain && sport != .hiking && sport != .trailRunning
            }
        }
    }

    private(set) var activities: [Activity] = []
    private(set) var isLoading = false
    private(set) var reachedEnd = false
    var filter: Filter = .all
    var errorMessage: String?
    private var nextBefore: Date?
    private let api: APIClient

    init(api: APIClient) { self.api = api }

    var visible: [Activity] { activities.filter { filter.matches($0.sport) } }

    struct Month: Identifiable {
        var month: Date
        var items: [Activity]
        var id: Date { month }
    }

    /// Agrupadas por mes, de la más reciente a la más antigua.
    var months: [Month] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visible) { calendar.dateInterval(of: .month, for: $0.startAt)?.start ?? $0.startAt }
        return grouped.keys.sorted(by: >).map { Month(month: $0, items: grouped[$0]!.sorted { $0.startAt > $1.startAt }) }
    }

    var totals: (count: Int, km: Double, gain: Double, summits: Int) {
        let list = visible
        return (list.count,
                list.compactMap(\.distanceM).reduce(0, +) / 1000,
                list.compactMap(\.elevGainM).reduce(0, +),
                list.reduce(0) { $0 + ($1.ascents?.count ?? 0) })
    }

    func reload() async {
        activities = []
        nextBefore = nil
        reachedEnd = false
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.activities(before: nextBefore, limit: 100)
            let known = Set(activities.map(\.id))
            activities += page.activities.filter { !known.contains($0.id) }
            nextBefore = page.nextBefore
            reachedEnd = page.nextBefore == nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Perfil → Actividades: todas tus salidas de montaña, con sus cifras y las cimas alcanzadas.
struct MountainActivitiesView: View {
    @Environment(\.apiClient) private var api
    @State private var store: MountainActivitiesStore?

    var body: some View {
        Group {
            if let store { content(store) } else { ProgressView() }
        }
        .background(Theme.Colors.groupedBackground)
        .navigationTitle("Actividades")
        .task {
            if store == nil {
                let created = MountainActivitiesStore(api: api)
                store = created
                await created.reload()
            }
        }
    }

    @ViewBuilder private func content(_ store: MountainActivitiesStore) -> some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.m, pinnedViews: []) {
                Picker("Tipo", selection: $store.filter) {
                    ForEach(MountainActivitiesStore.Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                let totals = store.totals
                Card(elevation: .medium) {
                    StatRow(stats: [
                        ("Salidas", "\(totals.count)", nil),
                        ("Distancia", totals.km.groupedInteger, "km"),
                        ("Desnivel", totals.gain.groupedInteger, "m"),
                        ("Cimas", "\(totals.summits)", nil),
                    ])
                }
                .staggeredAppear(0)

                if store.visible.isEmpty && !store.isLoading {
                    EmptyStateView(
                        icon: "figure.hiking",
                        title: "Sin actividades de montaña",
                        message: "Las salidas de senderismo y trail de Apple Watch, Polar o tus archivos aparecerán aquí, con o sin cimas."
                    )
                }

                ForEach(store.months) { month in
                    VStack(spacing: Theme.Spacing.s) {
                        Text(month.month.formatted(.dateTime.month(.wide).year()).capitalized)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Spacing.s)
                        ForEach(month.items) { activity in
                            NavigationLink { ActivityDetailView(activity: activity) } label: {
                                MountainActivityRow(activity: activity)
                            }
                            .buttonStyle(.pressableCard)
                            .scrollDepth()
                        }
                    }
                }

                if !store.reachedEnd {
                    ProgressView()
                        .padding()
                        .onAppear { Task { await store.loadMore() } }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
            .animation(Theme.Motion.spring, value: store.filter)
        }
        .refreshable { await store.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .sarrioLibraryChanged)) { _ in
            Task { await store.reload() }
        }
    }
}

/// Fila de actividad: deporte, título, fecha, cifras y las cimas alcanzadas.
struct MountainActivityRow: View {
    var activity: Activity

    private var summits: Int { activity.ascents?.count ?? 0 }

    var body: some View {
        Card(elevation: .low) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                SportBadge(sport: activity.sport, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(activity.sport.title) · \(activity.startAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                summitsTag
            }
            HStack(spacing: Theme.Spacing.l) {
                metric(((activity.distanceM ?? 0) / 1000).formatted(.number.precision(.fractionLength(1))), "km")
                metric((activity.elevGainM ?? 0).groupedInteger, "m D+")
                metric(duration, nil)
                Spacer()
            }
            .padding(.top, 2)
            if let names = activity.ascents?.map(\.peak.displayName), !names.isEmpty {
                Text(names.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .lineLimit(1)
            }
        }
    }

    private var summitsTag: some View {
        HStack(spacing: 4) {
            Image(systemName: summits > 0 ? "mountain.2.fill" : "flag.slash").font(.system(size: 10, weight: .bold))
            Text(summits == 0 ? "Sin cimas" : summits == 1 ? "1 cima" : "\(summits) cimas")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(summits > 0 ? .white : Theme.Colors.textSecondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(summits > 0 ? AnyShapeStyle(Theme.Colors.accent) : AnyShapeStyle(Theme.Colors.groupedBackground), in: Capsule())
    }

    private func metric(_ value: String, _ unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            if let unit { Text(unit).font(.statUnit).foregroundStyle(Theme.Colors.textSecondary) }
        }
    }

    private var duration: String {
        guard let s = activity.durationS, s > 0 else { return "–" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
}
