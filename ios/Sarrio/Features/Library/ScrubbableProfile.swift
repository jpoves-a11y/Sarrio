import SarrioKit
import SwiftUI

/// Perfil de elevación que se recorre con el dedo: una línea vertical, un punto y una etiqueta con
/// la altitud, la distancia y el desnivel acumulado en ese punto. Vibra suave a cada paso.
struct ScrubbableProfile: View {
    let plan: ReplayPlan
    var height: CGFloat = 110
    /// Fracción del recorrido bajo el dedo (nil sin tocar); la usa quien quiera marcarla en el mapa.
    @Binding var fraction: Double?

    @State private var lastTick = -1

    var body: some View {
        let values = ElevationProfileView.values(plan)
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: height)
            ZStack(alignment: .topLeading) {
                ElevationProfileView(plan: plan, fraction: 1, baseColor: Theme.Colors.separator, showsMarker: false, lineWidth: 2.4)
                    .frame(height: height)
                    .opacity(fraction == nil ? 1 : 0.55)

                if let f = fraction, let p = ElevationProfileView.point(at: f, values: values, size: size) {
                    // Línea vertical, punto y etiqueta
                    Rectangle()
                        .fill(Theme.Colors.textPrimary.opacity(0.35))
                        .frame(width: 1, height: height)
                        .offset(x: p.x - 0.5)
                    Circle()
                        .fill(Theme.Colors.surface)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.Colors.accent, lineWidth: 2.5))
                        .offset(x: p.x - 5.5, y: p.y - 5.5)
                    label(at: f)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            // Centrada sobre el punto, sin salirse por los lados
                            let x = p.x - d.width / 2
                            return -min(max(0, x), max(0, size.width - d.width))
                        }
                        .offset(y: -38)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = min(1, max(0, value.location.x / max(1, geo.size.width)))
                        if fraction == nil { withAnimation(.easeOut(duration: 0.12)) { fraction = f } } else { fraction = f }
                        // Un toque suave cada 1 % del recorrido
                        let tick = Int(f * 100)
                        if tick != lastTick {
                            lastTick = tick
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.25)) { fraction = nil }
                        lastTick = -1
                    }
            )
        }
        .frame(height: height)
        .padding(.top, 40)
        .accessibilityElement()
        .accessibilityLabel("Perfil de elevación")
        .accessibilityValue(summary)
    }

    private func label(at f: Double) -> some View {
        let d = plan.length * f
        let ele = plan.elevation(at: d)
        return HStack(spacing: Theme.Spacing.s) {
            if let ele {
                value(ele.groupedInteger, "m")
            }
            value((d / 1000).formatted(.number.precision(.fractionLength(1))), "km")
            value("+" + plan.elevationGain(upTo: d).groupedInteger, "m D+")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .elevation(.medium)
    }

    private func value(_ v: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(v).font(.sarrio(14, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(unit).font(.sarrio(11, .medium)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var summary: String {
        let values = plan.elevations.compactMap { $0 }
        guard let lo = values.min(), let hi = values.max() else { return "" }
        return "De \(Int(lo)) a \(Int(hi)) metros en \((plan.length / 1000).formatted(.number.precision(.fractionLength(1)))) kilómetros"
    }
}
