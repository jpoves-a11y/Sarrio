import SwiftUI

/// Lo que celebra una subida (sus cumbres y luego sus emblemas), uno detrás de otro en la misma
/// pantalla. Cada uno se ve entero; tocar durante la animación la completa y tocar ya asentado avanza.
struct BadgeCelebrationSequence: View {
    @Environment(AchievementsStore.self) private var achievements

    var body: some View {
        ZStack {
            if let item = achievements.current {
                let position = achievements.pending.count > 1 ? (achievements.index + 1, achievements.pending.count) : nil
                let isLast = achievements.index + 1 >= achievements.pending.count
                let onNext = { withAnimation(.easeInOut(duration: 0.35)) { achievements.advance() } }
                Group {
                    switch item {
                    case .summits(let summits):
                        SummitCelebrationView(celebration: summits, position: position, isLast: isLast, onNext: onNext)
                    case .badge(let badge):
                        BadgeCelebrationView(badge: badge, position: position, isLast: isLast, onNext: onNext)
                    }
                }
                .id(item.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
        }
    }
}

/// Emblema nuevo: el medallón cae girando en 3D, se asienta con un muelle y vibra.
struct BadgeCelebrationView: View {
    var badge: NewBadge
    /// «2 de 3» cuando hay varios.
    var position: (Int, Int)?
    var isLast = true
    var onNext: () -> Void = {}
    @State private var landed = false
    @State private var spin: Double = 540
    @State private var settled = false

    private var legend: Bool { badge.tier == .legend }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if let position {
                Text("\(position.0) de \(position.1)")
                    .font(.sarrio(12, .semibold).monospacedDigit())
                    .foregroundStyle(legend ? .white.opacity(0.6) : Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.m)
            }
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
                .motionSheen(enabled: legend && settled)
                .interactiveTilt(maxAngle: 12)
                .frame(width: 230, height: 230)
                // Las Leyendas se encienden al asentarse
                .background { if legend { LegendAura(size: 230, intensity: settled ? 1 : 0).animation(.easeIn(duration: 0.8), value: settled) } }

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
            Button(isLast ? "Seguir" : "Siguiente") { onNext() }
                .disabled(!settled)
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
                .opacity(settled ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(legend ? LegendColors.ink : Theme.Colors.page)
        // Tocar: durante la animación la completa; ya asentado, pasa al siguiente
        .contentShape(Rectangle())
        .onTapGesture {
            if settled { onNext() } else { finishNow() }
        }
        .sensoryFeedback(.success, trigger: settled) { _, now in now }
        .task {
            // Espera a que la pantalla esté presentada: la caída se ve entera
            try? await Task.sleep(for: .milliseconds(350))
            guard !settled else { return }
            // Cae girando…
            withAnimation(.spring(response: 0.85, dampingFraction: 0.62)) {
                landed = true
                spin = 0
            }
            try? await Task.sleep(for: .milliseconds(650))
            // …y se asienta
            guard !settled else { return }
            withAnimation(Theme.Motion.spring) { settled = true }
        }
    }

    /// Salta la animación al estado final (sin pasar al siguiente emblema).
    private func finishNow() {
        withAnimation(.easeOut(duration: 0.2)) {
            landed = true
            spin = 0
            settled = true
        }
    }
}
