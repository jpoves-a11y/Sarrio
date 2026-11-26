import SarrioKit
import SwiftUI

/// Hoja que aparece tras importar: celebra las cumbres nuevas o explica que no hubo ninguna.
struct ImportResultView: View {
    var outcome: ActivitySync.Outcome
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .scaleEffect(revealed ? 1 : 0.6)
                Circle()
                    .fill(LinearGradient(colors: [Theme.Colors.accent.opacity(0.9), Theme.Colors.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 76, height: 76)
                    .elevation(.high)
                    .overlay(
                        Image(systemName: outcome.ascents.isEmpty ? "figure.hiking" : "mountain.2.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .rotation3DEffect(.degrees(revealed ? 0 : 90), axis: (x: 0, y: 1, z: 0))
            }
            .padding(.top, Theme.Spacing.l)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(outcome.activity.displayTitle + " · " + outcome.activity.startAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !outcome.ascents.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(outcome.ascents.enumerated()), id: \.element.id) { index, ascent in
                        HStack(spacing: Theme.Spacing.m) {
                            PeakBadge(count: 1, size: 38)
                            Text(ascent.peak.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            if let ele = ascent.peak.ele {
                                Text("\(ele.groupedInteger) m").font(.system(size: 17, weight: .bold).monospacedDigit())
                            }
                        }
                        .padding(Theme.Spacing.m)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .elevation(.low)
                        .staggeredAppear(index + 2)
                    }
                }
            }

            Spacer(minLength: 0)
            Button("Hecho") { dismiss() }.buttonStyle(.primary)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.groupedBackground)
        .sensoryFeedback(.success, trigger: revealed)
        .onAppear { withAnimation(Theme.Motion.spring.delay(0.1)) { revealed = true } }
    }

    private var title: String {
        if !outcome.isNew { return "Ya tenías esta actividad" }
        switch outcome.ascents.count {
        case 0: return "Actividad guardada"
        case 1: return "¡Nueva cumbre!"
        default: return "¡\(outcome.ascents.count) cumbres!"
        }
    }
}
