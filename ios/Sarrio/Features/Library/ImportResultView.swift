import SarrioKit
import SwiftUI

/// Hoja que aparece tras importar: celebra las cumbres nuevas o explica que no hubo ninguna.
struct ImportResultView: View {
    var outcome: ActivitySync.Outcome
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            // Un símbolo fino que sube y aparece, con un filo debajo
            VStack(spacing: 10) {
                Image(systemName: outcome.ascents.isEmpty ? "figure.hiking" : "mountain.2")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Theme.Colors.accent)
                    .offset(y: revealed ? 0 : 14)
                    .opacity(revealed ? 1 : 0)
                Rectangle().fill(Theme.Colors.accent).frame(width: revealed ? 48 : 0, height: 1.5)
            }
            .padding(.top, Theme.Spacing.l)

            VStack(spacing: 6) {
                Text(title)
                    .font(.sarrio(24, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(outcome.activity.displayTitle + " · " + outcome.activity.startAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.sarrio(15))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !outcome.ascents.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(outcome.ascents.enumerated()), id: \.element.id) { index, ascent in
                        HStack(spacing: Theme.Spacing.m) {
                            PeakBadge(count: 1, size: 38)
                            Text(ascent.peak.displayName).font(.sarrio(17, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            if let ele = ascent.peak.ele {
                                Text("\(ele.groupedInteger) m").font(.sarrio(17, .bold).monospacedDigit())
                            }
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
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
