import Charts
import SarrioKit
import SwiftUI

/// «Análisis» de una salida: Pendiente | Ritmo | Parciales, un gráfico cada vez. Sin tiempos en la
/// ruta (algunas importaciones) solo hay Pendiente.
struct ActivityAnalysisSection: View {
    let analysis: ActivityAnalysis
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeader(title: "Análisis")
                if analysis.hasTimes {
                    Picker("", selection: $tab) {
                        Text("Pendiente").tag(0)
                        Text("Ritmo").tag(1)
                        Text("Parciales").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            Group {
                switch analysis.hasTimes ? tab : 0 {
                case 1: RateChart(analysis: analysis)
                case 2: SplitsChart(splits: analysis.splits)
                default: SlopeBars(analysis: analysis)
                }
            }
            .transition(.opacity)
            .animation(Theme.Motion.spring, value: tab)
        }
    }
}

/// Colores de pendiente: de suave a muy dura (los mismos del perfil coloreado).
enum SlopeColor {
    static func color(forGrade g: Double) -> Color {
        switch abs(g) {
        case ..<5: Color(red: 0.55, green: 0.75, blue: 0.45)
        case ..<10: Color(red: 0.85, green: 0.78, blue: 0.30)
        case ..<20: Color(red: 0.95, green: 0.58, blue: 0.20)
        case ..<30: Color(red: 0.90, green: 0.33, blue: 0.16)
        default: Color(red: 0.70, green: 0.12, blue: 0.14)
        }
    }
}

private struct SlopeBars: View {
    let analysis: ActivityAnalysis

    var body: some View {
        let b = analysis.buckets
        let rows: [(String, Double, Double)] = [
            ("Llano · <5 %", b.flat, 2), ("Suave · 5-10 %", b.easy, 7), ("Media · 10-20 %", b.moderate, 15),
            ("Dura · 20-30 %", b.hard, 25), ("Muy dura · >30 %", b.veryHard, 35),
        ]
        let total = max(1, b.total)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let h = analysis.hardest, h.grade >= 5 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(h.grade.rounded())) %").font(.sarrio(28, .bold).monospacedDigit()).foregroundStyle(SlopeColor.color(forGrade: h.grade))
                    Text("en \(Int(h.length.rounded())) m: el tramo más duro, en el km \((h.start / 1000).formatted(.number.precision(.fractionLength(1))))")
                        .font(.sarrio(13)).foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.0).font(.sarrio(13, .medium)).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\((row.1 / 1000).formatted(.number.precision(.fractionLength(1)))) km · \(Int((row.1 / total * 100).rounded())) %")
                            .font(.sarrio(12, .medium).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.Colors.separator)
                            Rectangle().fill(SlopeColor.color(forGrade: row.2)).frame(width: geo.size.width * CGFloat(row.1 / total))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

private struct RateChart: View {
    let analysis: ActivityAnalysis
    @State private var selected: Double?

    var body: some View {
        let points = analysis.rates.map { (minute: $0.time / 60, rate: $0.rate) }
        let hit = selected.flatMap { s in points.min { abs($0.minute - s) < abs($1.minute - s) } }
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.l) {
                if let best = analysis.bestClimb15 { figure(best.groupedInteger, "m/h · mejor 15 min") }
                if let moving = analysis.movingSeconds { figure(duration(moving), "en movimiento") }
                if let stopped = analysis.stoppedSeconds, stopped > 60 { figure(duration(stopped), "parado") }
            }
            Text(hit.map { "\(Int($0.rate.rounded())) m/h · min \(Int($0.minute))" } ?? " ")
                .font(.sarrio(12, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("min", p.minute), y: .value("m/h", p.rate), width: .fixed(3))
                        .foregroundStyle(p.rate >= 0 ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.45))
                }
                RuleMark(y: .value("0", 0)).foregroundStyle(Theme.Colors.separator)
                if let hit {
                    RuleMark(x: .value("min", hit.minute)).foregroundStyle(Theme.Colors.textPrimary.opacity(0.25))
                }
            }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel { if let m = v.as(Double.self) { Text(m >= 60 ? "\(Int(m) / 60) h" : "\(Int(m))'").font(.sarrio(10)) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Theme.Colors.separator)
                    AxisValueLabel().font(.sarrio(10))
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 170)
            HStack(spacing: Theme.Spacing.m) {
                Label("Subiendo", systemImage: "square.fill").font(.sarrio(11)).foregroundStyle(Theme.Colors.accent)
                Label("Bajando", systemImage: "square.fill").font(.sarrio(11)).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func figure(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.sarrio(20, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(label).font(.sarrio(11)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func duration(_ s: Double) -> String {
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(m)" : "\(m) min"
    }
}

private struct SplitsChart: View {
    let splits: [ActivityAnalysis.Split]

    var body: some View {
        let timed = splits.filter { $0.seconds != nil }
        let fastest = timed.min { ($0.seconds ?? 0) < ($1.seconds ?? 0) }?.km
        let slowest = timed.max { ($0.seconds ?? 0) < ($1.seconds ?? 0) }?.km
        VStack(alignment: .leading, spacing: 0) {
            ForEach(splits, id: \.km) { s in
                HStack(spacing: Theme.Spacing.s) {
                    Text("\(s.km)").font(.sarrio(13, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary).frame(width: 22, alignment: .leading)
                    Text(s.seconds.map(pace) ?? "—")
                        .font(.sarrio(15, .semibold).monospacedDigit())
                        .foregroundStyle(s.km == fastest ? Theme.Colors.accent : Theme.Colors.textPrimary)
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { geo in
                        let maxS = max(1, timed.compactMap(\.seconds).max() ?? 1)
                        Rectangle()
                            .fill(s.km == fastest ? Theme.Colors.accent : s.km == slowest ? Theme.Colors.textSecondary.opacity(0.5) : Theme.Colors.accent.opacity(0.35))
                            .frame(width: geo.size.width * CGFloat((s.seconds ?? 0) / maxS), height: 8)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(maxHeight: .infinity)
                    }
                    Text("+\(Int(s.gain)) / −\(Int(s.loss))").font(.sarrio(11, .medium).monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 78, alignment: .trailing)
                }
                .frame(height: 30)
            }
            if let fastest, let slowest, fastest != slowest {
                Text("Más rápido el km \(fastest), más lento el \(slowest)")
                    .font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary).padding(.top, Theme.Spacing.s)
            }
        }
    }

    private func pace(_ s: Double) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return "\(m):\(String(format: "%02d", sec))"
    }
}

// MARK: - Contra tus otras veces

/// Si ya habías subido esta cima: tu tiempo hasta la cumbre en cada vez, con la mejor destacada.
struct SummitHistory: View {
    let peak: PeakRef
    /// (fecha, segundos desde el inicio de la salida hasta la cima, es esta)
    let entries: [(date: Date, seconds: Double, current: Bool)]

    var body: some View {
        let best = entries.min { $0.seconds < $1.seconds }
        let current = entries.first { $0.current }
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "\(peak.displayName) · tus \(entries.count) veces")
            if let current, let best {
                let others = entries.filter { !$0.current }
                if let bestOther = others.min(by: { $0.seconds < $1.seconds }) {
                    let diff = Int(((bestOther.seconds - current.seconds) / 60).rounded())
                    Text(diff > 0 ? "\(diff) min más rápido que tu mejor marca anterior" : diff < 0 ? "\(-diff) min más que tu mejor marca (\(time(bestOther.seconds)))" : "Igual que tu mejor marca")
                        .font(.sarrio(15, .semibold))
                        .foregroundStyle(diff > 0 ? Theme.Colors.accent : Theme.Colors.textPrimary)
                }
                Chart {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        LineMark(x: .value("Fecha", e.date), y: .value("min", e.seconds / 60))
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                        PointMark(x: .value("Fecha", e.date), y: .value("min", e.seconds / 60))
                            .foregroundStyle(e.current ? Theme.Colors.accent : (e.seconds == best.seconds ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                            .symbolSize(e.current ? 110 : 55)
                            .annotation(position: .top) {
                                Text(time(e.seconds)).font(.sarrio(10, e.current ? .bold : .medium)).foregroundStyle(e.current ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.sarrio(10)) } }
                .frame(height: 140)
            }
        }
    }

    private func time(_ s: Double) -> String {
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(m)" : "\(m) min"
    }
}
