import SwiftUI

/// Emblemas: los totales arriba sin marco, los últimos conseguidos, los más cerca de caer y
/// todo el catálogo por categorías (conseguidos en metal, pendientes en gris con su progreso).
struct BadgesView: View {
    @Environment(AchievementsStore.self) private var store
    @State private var selected: Badge?

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: Theme.Spacing.m, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let catalog = store.catalog {
                    totals(catalog)
                    if let legends = store.categories.first(where: { $0.name == "Leyendas" }) {
                        legendsBand(legends.badges)
                    }
                    if !store.earned.isEmpty {
                        strip(title: "Últimos conseguidos", badges: Array(store.earned.prefix(8)))
                    }
                    if !store.closest.isEmpty {
                        strip(title: "Muy cerca", badges: Array(store.closest.prefix(8)))
                    }
                    ForEach(store.categories.filter { $0.name != "Leyendas" }, id: \.name) { category in
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            SectionHeader(title: category.name)
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                                ForEach(Array(category.badges.enumerated()), id: \.element.id) { index, badge in
                                    cell(badge).staggeredAppear(index)
                                }
                            }
                        }
                    }
                } else if let error = store.errorMessage {
                    EmptyStateView(icon: "medal", title: "No se han podido cargar", message: error, actionTitle: "Reintentar") {
                        Task { await store.loadBadges() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Emblemas")
        .task { await store.loadBadges() }
        .refreshable { await store.loadBadges() }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Partes

    private func totals(_ catalog: BadgeCatalog) -> some View {
        let earned = store.earned
        let count = { (tier: BadgeTier) in earned.filter { $0.tier == tier }.count }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(catalog.earned)").font(.heroValue).foregroundStyle(Theme.Colors.textPrimary)
                Text("de \(catalog.total)").font(.sarrio(17, .medium)).foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.l) {
                tierCount("Bronce", count(.bronze))
                tierCount("Plata", count(.silver))
                tierCount("Oro", count(.gold) + count(.special))
                if count(.legend) > 0 { tierCount("Leyenda", count(.legend)) }
            }
            // Barra fina de todo el catálogo
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Colors.separator)
                    Rectangle().fill(Theme.Colors.accent)
                        .frame(width: geo.size.width * CGFloat(catalog.earned) / CGFloat(max(catalog.total, 1)))
                }
            }
            .frame(height: 2)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    /// Las Leyendas, en una banda de obsidiana: medallones en oro, apagados hasta conseguirlos.
    private func legendsBand(_ badges: [Badge]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("LEYENDAS")
                .font(.sarrio(12, .semibold))
                .tracking(2)
                .foregroundStyle(LegendColors.gold)
                .padding(.horizontal, Theme.Spacing.m)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(badges) { badge in
                        Button { selected = badge } label: {
                            VStack(spacing: 6) {
                                BadgeMedal(icon: badge.icon, earned: true, size: 80, shine: badge.isEarned)
                                    .opacity(badge.isEarned ? 1 : 0.5)
                                Text(badge.name)
                                    .font(.sarrio(13, .semibold))
                                    .foregroundStyle(badge.isEarned ? .white : .white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let text = badge.progressText {
                                    Text(text)
                                        .font(.sarrio(11, .medium).monospacedDigit())
                                        .foregroundStyle(LegendColors.gold)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
            }
        }
        .padding(.vertical, Theme.Spacing.l)
        .background(LegendColors.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .elevation(.high)
    }

    private func tierCount(_ title: String, _ value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)").font(.sarrio(15, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(title.lowercased()).font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func strip(title: String, badges: [Badge]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(badges) { badge in cell(badge).frame(width: 96) }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func cell(_ badge: Badge) -> some View {
        Button {
            selected = badge
        } label: {
            VStack(spacing: 6) {
                BadgeMedal(icon: badge.icon, earned: badge.isEarned, progress: badge.progress?.fraction, size: 76)
                    .elevation(badge.isEarned ? .medium : .low)
                Text(badge.name)
                    .font(.sarrio(13, .semibold))
                    .foregroundStyle(badge.isEarned ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let earnedAt = badge.earnedAt {
                    Text(earnedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.sarrio(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if let text = badge.progressText {
                    Text(text)
                        .font(.sarrio(11, .medium).monospacedDigit())
                        .foregroundStyle(Theme.Colors.accent)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }
}

/// Ficha de un emblema: el medallón grande, que se inclina al dedo y brilla, con la condición,
/// la fecha y la actividad con que se ganó (o lo que falta).
struct BadgeDetailView: View {
    var badge: Badge
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    BadgeMedal(icon: badge.icon, earned: badge.isEarned || badge.tier == .legend,
                               progress: badge.progress?.fraction, size: 220, shine: badge.isEarned)
                        .opacity(badge.tier == .legend && !badge.isEarned ? 0.6 : 1)
                        .elevation(badge.isEarned ? .high : .low)
                        .interactiveTilt(maxAngle: 14)
                        .frame(width: 220, height: 220)
                        .padding(.top, Theme.Spacing.l)

                    VStack(spacing: Theme.Spacing.s) {
                        Text("\(badge.tier.title) · \(badge.category)".uppercased())
                            .font(.sarrio(12, .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(badge.name)
                            .font(.sarrio(30, .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(badge.description)
                            .font(.sarrio(16))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.m)

                    if let earnedAt = badge.earnedAt {
                        Card {
                            HStack {
                                Text("Conseguido").font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary)
                                Spacer()
                                Text(earnedAt.formatted(.dateTime.day().month(.wide).year()))
                                    .font(.sarrio(15, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }
                        if let activity = library.activities.first(where: { $0.id == badge.activityId }) {
                            NavigationLink { ActivityDetailView(activity: activity) } label: {
                                MountainActivityRow(activity: activity)
                            }
                            .buttonStyle(.pressableCard)
                        }
                    } else if let progress = badge.progress, let text = badge.progressText {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Llevas").font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary)
                                Spacer()
                                Text(text).font(.sarrio(17, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                            }
                            ProgressBar(fraction: progress.fraction)
                        }
                    } else {
                        Text("Aún no lo tienes")
                            .font(.sarrio(15, .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .background(Theme.Colors.page)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }
}

/// Barra de progreso fina, del color de acento.
struct ProgressBar: View {
    var fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Colors.separator)
                Rectangle().fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .animation(Theme.Motion.spring, value: fraction)
    }
}
