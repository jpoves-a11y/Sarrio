import SwiftUI

/// Categorías de retos, de la más fácil a la más difícil.
enum ChallengeCategory: Int, CaseIterable, Comparable {
    case own, month, season, year, lists, legends

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func of(_ c: Challenge) -> ChallengeCategory {
        if c.isLegend { return .legends }
        if !c.official { return .own }
        if c.kind == .peaks { return .lists }
        if c.recurrence == "monthly" { return .month }
        if c.recurrence == "yearly" && c.window != nil { return .season }
        return .year
    }

    var title: String {
        switch self {
        case .own: "Tus retos"
        case .month: "Este mes"
        case .season: "Esta temporada"
        case .year: "Este año"
        case .lists: "Listas de cimas"
        case .legends: "Leyendas"
        }
    }
}

/// Pestaña Retos: todos los retos siempre activos (no hay que unirse), por categorías de más
/// fácil a más difícil. En cada una, primero lo que ya tienes o tienes más cerca. Una categoría
/// casi completada baja al final, para que arriba quede siempre lo factible.
struct ChallengesView: View {
    /// Dentro de Logros: sin título ni barra propios.
    var embedded = false
    @Environment(AchievementsStore.self) private var store
    @State private var creating = false

    private var sections: [(category: ChallengeCategory, items: [Challenge])] {
        let all = store.featured + store.mine.filter { m in !store.featured.contains { $0.id == m.id } }
        let grouped = Dictionary(grouping: all, by: ChallengeCategory.of)
        let unsorted = grouped.map { category, items in
            (category: category, items: items.sorted(by: Self.closestFirst))
        }
        return unsorted.sorted { a, b in
            // Tus retos siempre arriba y las Leyendas siempre al final
            if a.category == .own { return b.category != .own }
            if b.category == .own { return false }
            if a.category == .legends { return false }
            if b.category == .legends { return true }
            let ma = Self.mastered(a.items), mb = Self.mastered(b.items)
            if ma != mb { return !ma }
            return a.category < b.category
        }
    }

    /// Ya hechos y casi hechos primero; los que aún no han empezado, al final.
    private static func closestFirst(_ a: Challenge, _ b: Challenge) -> Bool {
        let ua = a.progress?.status == .upcoming, ub = b.progress?.status == .upcoming
        if ua != ub { return !ua }
        return (a.progress?.fraction ?? 0) > (b.progress?.fraction ?? 0)
    }

    /// Categoría casi completada (≥ 60 % de sus retos hechos).
    private static func mastered(_ items: [Challenge]) -> Bool {
        let done = items.filter { $0.progress?.done == true }.count
        return !items.isEmpty && Double(done) / Double(items.count) >= 0.6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if store.featured.isEmpty && store.mine.isEmpty {
                    if let error = store.errorMessage {
                        EmptyStateView(icon: "flag.checkered", title: "No se han podido cargar", message: error, actionTitle: "Reintentar") {
                            Task { await store.loadChallenges() }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                    }
                } else {
                    ForEach(sections, id: \.category) { section in
                        if section.category == .legends {
                            LegendsSection(legends: section.items)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                SectionHeader(title: section.category.title)
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, challenge in
                                    NavigationLink { ChallengeDetailView(challenge: challenge) } label: {
                                        ChallengeRow(challenge: challenge)
                                    }
                                    .buttonStyle(.pressableCard)
                                    .staggeredAppear(index)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle(ifNotEmbedded: embedded ? nil : "Retos")
        .toolbar {
            if !embedded {
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                }
                .accessibilityLabel("Crear reto")
            }
        }
        .task { await store.loadChallenges() }
        .refreshable { await store.loadChallenges() }
        .sheet(isPresented: $creating) { NavigationStack { CreateChallengeView() } }
    }
}

/// Fila de reto: icono, título, cifra y barra fina. Toda la fila abre el reto.
struct ChallengeRow: View {
    var challenge: Challenge

    var body: some View {
        let text = challenge.valueText
        let p = challenge.progress
        let done = p?.done == true
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            BadgeMedal(icon: challenge.medalIcon, earned: done, progress: p?.fraction, size: 52)
                .elevation(done ? .medium : .low)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(challenge.title)
                        .font(.sarrio(16, .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.s)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    } else if let period = challenge.periodText {
                        Text(period)
                            .font(.sarrio(12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text.value)
                        .font(.sarrio(15, .semibold).monospacedDigit())
                        .foregroundStyle(done ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    Text("/ \(text.target) \(text.unit)")
                        .font(.sarrio(13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .minimumScaleFactor(0.7)
                }
                ProgressBar(fraction: p?.fraction ?? 0, height: 2)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
        .opacity(p?.status == .upcoming ? 0.6 : 1)
    }
}

/// Icono fino del tipo de reto (relleno de acento cuando está hecho).
struct ChallengeIcon: View {
    var challenge: Challenge
    var done = false
    var size: CGFloat = 40

    private var symbol: String {
        if challenge.kind == .peaks { return "mountain.2" }
        switch challenge.metric {
        case .elevationGain, .maxActivityGain: return "arrow.up.right"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .activeWeeks: return "calendar"
        case .activities: return "figure.hiking"
        case .sunriseSummits: return "sunrise"
        case .highSummits: return "triangle"
        default: return "flag"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .light))
            .foregroundStyle(done ? .white : Theme.Colors.accent)
            .frame(width: size, height: size)
            .background(done ? Theme.Colors.accent : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .stroke(done ? .clear : Theme.Colors.separator, lineWidth: 1))
    }
}

/// Leyendas: bloque en obsidiana y oro, en vertical, con el medallón y su aura. Toda la fila
/// (medalla incluida) abre el reto.
struct LegendsSection: View {
    var legends: [Challenge]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LEYENDAS")
                .font(.sarrio(12, .semibold))
                .tracking(2)
                .foregroundStyle(LegendColors.gold)
                .padding(.bottom, Theme.Spacing.s)
            ForEach(legends) { legend in
                NavigationLink { ChallengeDetailView(challenge: legend) } label: { LegendRow(challenge: legend) }
                    .buttonStyle(.pressableCard)
            }
        }
        .padding(Theme.Spacing.m)
        .background(LegendColors.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        // Filo dorado tenue: separa el bloque del fondo también en modo oscuro
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).stroke(LegendColors.gold.opacity(0.28), lineWidth: 0.75))
        .elevation(.high)
    }
}

private struct LegendRow: View {
    var challenge: Challenge

    var body: some View {
        let p = challenge.progress
        let done = p?.done == true
        let text = challenge.valueText
        HStack(spacing: Theme.Spacing.m) {
            // Siempre en oro; apagado hasta conseguirlo
            BadgeMedal(icon: "badge-\(challenge.badgeId ?? "")", earned: true, size: 64, shine: done)
                .opacity(done ? 1 : 0.6)
                .legendAura(size: 64, intensity: done ? 1 : 0.35)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(challenge.title)
                    .font(.sarrio(16, .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text.value).font(.sarrio(15, .semibold).monospacedDigit()).foregroundStyle(LegendColors.gold)
                    Text("/ \(text.target) \(text.unit)").font(.sarrio(12)).foregroundStyle(.white.opacity(0.55))
                        .minimumScaleFactor(0.7)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.12))
                        Rectangle().fill(LegendColors.gold).frame(width: geo.size.width * CGFloat(p?.fraction ?? 0))
                    }
                }
                .frame(height: 2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
