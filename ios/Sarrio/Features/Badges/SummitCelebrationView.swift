import CoreLocation
import SwiftUI

/// Las cumbres de una salida recién subida, antes de sus emblemas: el relieve 3D de la más alta
/// girando con la ruta y las banderillas clavándose, su nombre y altitud, y el resto de cimas.
struct SummitCelebrationView: View {
    var celebration: SummitCelebration
    /// «1 de 3» cuando hay más cosas que celebrar.
    var position: (Int, Int)?
    var isLast = true
    var onNext: () -> Void = {}

    @Environment(LibraryStore.self) private var library
    @State private var settled = false
    @State private var shownAltitude: Double = 0

    private var ascents: [Ascent] { celebration.sortedAscents }
    private var top: Ascent? { ascents.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let position {
                Text("\(position.0) de \(position.1)")
                    .font(.sarrio(12, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            if let top {
                // El relieve de la cima más alta, girando, con la ruta y las banderillas
                Terrain3DView(
                    center: top.peak.coordinate,
                    distance: 2_600,
                    segments: [celebration.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }],
                    summits: ascents.map(\.peak),
                    orbit: true,
                    interactive: false
                )
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.42 }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .elevation(.high)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(ascents.count == 1 ? "CUMBRE" : "\(ascents.count) CUMBRES")
                        .font(.sarrio(12, .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(top.peak.displayName)
                        .font(.sarrio(32, .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        if top.peak.ele != nil {
                            Text("\(shownAltitude.groupedInteger) m")
                                .font(.sarrio(22, .semibold).monospacedDigit())
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .contentTransition(.numericText(value: shownAltitude))
                        }
                        if isFirstTime(top) { firstTimeTag }
                    }
                }
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : 12)

                // El resto de cimas de la salida
                if ascents.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(ascents.dropFirst().enumerated()), id: \.element.id) { index, ascent in
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: "triangle")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(Theme.Colors.accent)
                                Text(ascent.peak.displayName)
                                    .font(.sarrio(16, .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if isFirstTime(ascent) { firstTimeTag }
                                Spacer(minLength: Theme.Spacing.s)
                                if let ele = ascent.peak.ele {
                                    Text("\(ele.groupedInteger) m")
                                        .font(.sarrio(16, .semibold).monospacedDigit())
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
                            .opacity(settled ? 1 : 0)
                            .offset(y: settled ? 0 : 10)
                            .animation(Theme.Motion.spring.delay(0.15 + Double(index) * 0.08), value: settled)
                        }
                    }
                }

                Text(celebration.title + " · " + celebration.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.sarrio(14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .opacity(settled ? 1 : 0)
            }

            Spacer(minLength: 0)
            Button(isLast ? "Seguir" : "Siguiente") { onNext() }
                .buttonStyle(.primary)
                .disabled(!settled)
                .opacity(settled ? 1 : 0.4)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.page)
        .sensoryFeedback(.success, trigger: settled) { _, now in now }
        // Tocar: durante la animación la completa; ya asentada, avanza
        .contentShape(Rectangle())
        .onTapGesture {
            if settled { onNext() } else { finishNow() }
        }
        .task {
            // Las banderillas caen al aparecer el mapa; el texto llega cuando se clava la más alta
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !settled else { return }
            withAnimation(Theme.Motion.spring) { settled = true }
            withAnimation(.easeOut(duration: 1.1)) { shownAltitude = top?.peak.ele ?? 0 }
        }
    }

    private func finishNow() {
        withAnimation(.easeOut(duration: 0.2)) {
            settled = true
            shownAltitude = top?.peak.ele ?? 0
        }
    }

    /// Ninguna otra ascensión a ese pico en la biblioteca (sin contar esta salida).
    private func isFirstTime(_ ascent: Ascent) -> Bool {
        let others = (library.library?.ascents ?? []).filter { $0.peak.id == ascent.peak.id && $0.activityId != celebration.activityId }
        return others.isEmpty
    }

    private var firstTimeTag: some View {
        Text("PRIMERA VEZ")
            .font(.sarrio(10, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(Theme.Colors.accent, lineWidth: 1))
    }
}
