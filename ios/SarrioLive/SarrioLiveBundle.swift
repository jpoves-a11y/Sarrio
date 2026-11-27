import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SarrioLiveBundle: WidgetBundle {
    var body: some Widget {
        VideoExportLiveActivity()
    }
}

private let accent = Color("AccentColor")

/// El vídeo del replay preparándose: en la pantalla de bloqueo y en la isla dinámica.
struct VideoExportLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VideoExportAttributes.self) { context in
            LockScreenView(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("SarrioMark").resizable().scaledToFit().frame(height: 34)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentText)
                        .font(.sarrio(22, .bold).monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText(value: context.state.fraction))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.sarrio(15, .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressBar(fraction: context.state.fraction, paused: context.state.phase == .paused)
                        Text(context.state.statusText)
                            .font(.sarrio(12, .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .paused ? "pause.fill" : "film")
                    .foregroundStyle(accent)
            } compactTrailing: {
                ProgressRing(fraction: context.state.fraction)
                    .frame(width: 18, height: 18)
            } minimal: {
                ProgressRing(fraction: context.state.fraction)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let state: VideoExportAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                ProgressRing(fraction: state.fraction, lineWidth: 4)
                Image("SarrioMark").resizable().scaledToFit().padding(10)
                    .environment(\.colorScheme, .dark)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vídeo de \(title)")
                        .font(.sarrio(15, .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 6)
                    Text(state.percentText)
                        .font(.sarrio(17, .bold).monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText(value: state.fraction))
                }
                ProgressBar(fraction: state.fraction, paused: state.phase == .paused)
                Text(state.statusText)
                    .font(.sarrio(12, .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
    }
}

/// Barra fina de progreso con un brillo que la recorre mientras avanza.
private struct ProgressBar: View {
    let fraction: Double
    let paused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.18))
                RoundedRectangle(cornerRadius: 2)
                    .fill(paused ? Color.white.opacity(0.5) : accent)
                    .frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
        .animation(.easeInOut(duration: 0.6), value: fraction)
    }
}

private struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0.02, fraction)))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeInOut(duration: 0.6), value: fraction)
    }
}
