import SwiftUI

/// En Perfil: tu año en tres cifras grandes y el acceso a las estadísticas completas.
struct YearStrip: View {
    @Environment(\.apiClient) private var api
    @State private var totals: UserStats.Totals?
    private let year = Calendar.current.component(.year, from: .now)

    var body: some View {
        NavigationLink { StatsView() } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("TU \(String(year))")
                        .font(.sarrio(12, .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("Ver estadísticas")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                }
                HStack(spacing: 0) {
                    figure((totals?.gain ?? 0).groupedInteger, "m D+")
                    figure(((totals?.distance ?? 0) / 1000).groupedInteger, "km")
                    figure("\(totals?.summits ?? 0)", "cimas")
                }
            }
            .padding(.vertical, Theme.Spacing.m)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
        }
        .buttonStyle(.pressableCard)
        .task { totals = (try? await api.stats(year: year))?.totals }
    }

    private func figure(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.sarrio(26, .semibold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
            Text(unit).font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// En Amigos: la clasificación del mes entre tus amigos y tú (m D+, cimas o km).
struct MonthLeaderboard: View {
    @Environment(\.apiClient) private var api
    @State private var metric = "gain"
    @State private var board: Leaderboard?

    var body: some View {
        if let rows = board?.rows, rows.count >= 2 {
            let top = max(1, rows.map(\.value).max() ?? 1)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    SectionHeader(title: "Este mes")
                    Picker("", selection: $metric) {
                        Text("m D+").tag("gain")
                        Text("Cimas").tag("summits")
                        Text("km").tag("distance")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                    NavigationLink { UserProfileView(username: row.user.username) } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Text("\(index + 1)").font(.sarrio(13, .semibold).monospacedDigit())
                                .foregroundStyle(index == 0 ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                .frame(width: 16)
                            AvatarView(name: row.user.displayName, userId: row.user.id, avatarKey: row.user.avatarKey, size: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(row.isMe ? "Tú" : row.user.displayName)
                                        .font(.sarrio(14, row.isMe ? .bold : .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Spacer()
                                    Text(format(row.value)).font(.sarrio(14, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Theme.Colors.separator)
                                        Rectangle().fill(row.isMe ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.4))
                                            .frame(width: geo.size.width * CGFloat(row.value / top))
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(row.isMe)
                }
            }
            .padding(.vertical, Theme.Spacing.m)
            .animation(Theme.Motion.spring, value: metric)
            .task(id: metric) { await load() }
        } else {
            Color.clear.frame(height: 0).task(id: metric) { await load() }
        }
    }

    private func load() async {
        if let fresh = try? await api.leaderboard(metric: metric) { board = fresh }
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case "distance": "\((v / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        case "summits": "\(Int(v))"
        default: "\(v.groupedInteger) m"
        }
    }
}
