import SwiftUI

/// Pestaña Retos: los míos en curso (cifra grande y barra fina), los de temporada y las listas
/// de cimas oficiales para unirme, y crear uno propio.
struct ChallengesView: View {
    @Environment(AchievementsStore.self) private var store
    @State private var creating = false

    private var joinedIds: Set<String> { Set(store.joined.map(\.id)) }
    private var seasonal: [Challenge] { store.featured.filter { $0.kind == .metric && !joinedIds.contains($0.id) } }
    private var lists: [Challenge] { store.featured.filter { $0.kind == .peaks && !joinedIds.contains($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if store.featured.isEmpty && store.joined.isEmpty {
                    if let error = store.errorMessage {
                        EmptyStateView(icon: "flag.checkered", title: "No se han podido cargar", message: error, actionTitle: "Reintentar") {
                            Task { await store.loadChallenges() }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                    }
                } else {
                    section("En curso") {
                        if store.joined.isEmpty {
                            Text("Únete a un reto de temporada o a una lista de cimas y verás aquí cómo vas.")
                                .font(.sarrio(15))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, Theme.Spacing.s)
                        }
                        ForEach(Array(store.joined.enumerated()), id: \.element.id) { index, challenge in
                            NavigationLink { ChallengeDetailView(challenge: challenge) } label: {
                                ActiveChallengeRow(challenge: challenge)
                            }
                            .buttonStyle(.pressableCard)
                            .staggeredAppear(index)
                        }
                    }
                    if !seasonal.isEmpty {
                        section("Retos de temporada") {
                            ForEach(seasonal) { challenge in OpenChallengeRow(challenge: challenge) }
                        }
                    }
                    if !lists.isEmpty {
                        section("Listas de cimas") {
                            ForEach(lists) { challenge in OpenChallengeRow(challenge: challenge) }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Retos")
        .toolbar {
            Button { creating = true } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .regular))
            }
            .accessibilityLabel("Crear reto")
        }
        .task { await store.loadChallenges() }
        .refreshable { await store.loadChallenges() }
        .sheet(isPresented: $creating) { NavigationStack { CreateChallengeView() } }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: title)
            content()
        }
    }
}

/// Reto al que estoy unido: la cifra grande, la meta, una barra fina y lo que queda de periodo.
struct ActiveChallengeRow: View {
    var challenge: Challenge

    var body: some View {
        let text = challenge.valueText
        let p = challenge.progress
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(challenge.title)
                    .font(.sarrio(17, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.s)
                if p?.done == true {
                    Label("Hecho", systemImage: "checkmark")
                        .font(.sarrio(13, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                } else if let period = challenge.periodText {
                    Text(period).font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(text.value)
                    .font(.sarrio(34, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.6)
                Text("/ \(text.target) \(text.unit)")
                    .font(.sarrio(15, .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
            }
            ProgressBar(fraction: p?.fraction ?? 0)
        }
    }
}

/// Reto oficial al que aún no estoy unido, con «Unirme».
struct OpenChallengeRow: View {
    var challenge: Challenge
    @Environment(AchievementsStore.self) private var store
    @State private var joining = false

    var body: some View {
        NavigationLink { ChallengeDetailView(challenge: challenge) } label: {
            Card {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    ChallengeIcon(challenge: challenge)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(challenge.title)
                            .font(.sarrio(16, .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.sarrio(13))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    Button {
                        joining = true
                        Task {
                            await store.setJoined(challenge, true)
                            joining = false
                        }
                    } label: {
                        Group {
                            if joining { ProgressView().controlSize(.small) } else { Text("Unirme") }
                        }
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minWidth: 64, minHeight: 32)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(Theme.Colors.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: joining) { _, now in now }
                }
            }
        }
        .buttonStyle(.pressableCard)
    }

    private var subtitle: String {
        if challenge.kind == .peaks {
            let n = challenge.peakCount ?? 0
            let done = Int(challenge.progress?.value ?? 0)
            return done > 0 ? "\(n) cimas · ya tienes \(done)" : "\(n) cimas"
        }
        let text = challenge.valueText
        return "\(text.target) \(text.unit) · \(challenge.periodKind)"
    }
}

/// Icono fino del tipo de reto.
struct ChallengeIcon: View {
    var challenge: Challenge
    var size: CGFloat = 36

    private var symbol: String {
        if challenge.kind == .peaks { return "mountain.2" }
        switch challenge.metric {
        case .elevationGain: return "arrow.up.right"
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
            .font(.system(size: size * 0.46, weight: .light))
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(Theme.Colors.separator, lineWidth: 1))
    }
}
