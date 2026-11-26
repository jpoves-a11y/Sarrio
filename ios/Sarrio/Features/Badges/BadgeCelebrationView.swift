import SwiftUI

/// Emblema nuevo: el medallón cae girando en 3D, se asienta con un muelle y vibra.
struct BadgeCelebrationView: View {
    var badge: NewBadge
    @Environment(\.dismiss) private var dismiss
    @State private var landed = false
    @State private var spin: Double = 540
    @State private var settled = false

    private var legend: Bool { badge.tier == .legend }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: Theme.Spacing.l)
            Text(legend ? "ERES LEYENDA" : "NUEVO EMBLEMA")
                .font(.sarrio(12, .semibold))
                .tracking(1.6)
                .foregroundStyle(legend ? LegendColors.gold : Theme.Colors.accent)
                .opacity(settled ? 1 : 0)

            BadgeMedal(icon: badge.icon, earned: true, size: 230, shine: settled)
                .elevation(.high)
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .scaleEffect(landed ? 1 : 0.55)
                .offset(y: landed ? 0 : -420)
                .interactiveTilt(maxAngle: 12)
                .frame(width: 230, height: 230)

            VStack(spacing: Theme.Spacing.s) {
                Text(badge.name)
                    .font(.sarrio(32, .bold))
                    .foregroundStyle(legend ? .white : Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(badge.description)
                    .font(.sarrio(16))
                    .foregroundStyle(legend ? .white.opacity(0.65) : Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(badge.tier.title) · \(badge.category)".uppercased())
                    .font(.sarrio(11, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 16)

            Spacer()
            Button("Seguir") { dismiss() }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
                .opacity(settled ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(legend ? LegendColors.ink : Theme.Colors.page)
        .sensoryFeedback(.success, trigger: settled) { _, now in now }
        .task {
            // Cae girando…
            withAnimation(.spring(response: 0.85, dampingFraction: 0.62)) {
                landed = true
                spin = 0
            }
            try? await Task.sleep(for: .milliseconds(650))
            // …y se asienta
            withAnimation(Theme.Motion.spring) { settled = true }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!settled)
    }
}
