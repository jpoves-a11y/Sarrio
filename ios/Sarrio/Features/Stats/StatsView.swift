import Charts
import SwiftUI

/// Estadísticas del perfil: el año (o siempre) en cifras, el desnivel, tu cordillera, el calendario,
/// los récords, la velocidad de subida y todas tus rutas. De lo más impactante a lo más detallado.
struct StatsView: View {
    @Environment(\.apiClient) private var api
    @State private var year: Int? = Calendar.current.component(.year, from: .now)
    @State private var stats: UserStats?
    @State private var errorMessage: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                periodPicker
                if let stats {
                    YearHero(stats: stats, year: year)
                    GainChart(stats: stats, year: year)
                    if !stats.peaks.isEmpty { Ridge3DBlock(peaks: stats.peaks) }
                    CalendarHeatmap(calendar: stats.calendar, streak: stats.streak)
                    RecordsRow(records: stats.records)
                    if stats.climbRates.count >= 2 { ClimbRateChart(points: stats.climbRates) }
                    AllRoutesBlock()
                } else if let errorMessage {
                    EmptyStateView(icon: "chart.xyaxis.line", title: "No se han podido cargar", message: errorMessage,
                                   actionTitle: "Reintentar") { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(Theme.Spacing.m)
            .animation(Theme.Motion.spring, value: year)
        }
        .background(Theme.Colors.page)
        .navigationTitle("Estadísticas")
        .task(id: year) { await load() }
    }

    /// 2026 ▾ (los años con salidas) | Siempre
    private var periodPicker: some View {
        let years = stats?.years ?? [Calendar.current.component(.year, from: .now)]
        return HStack(spacing: Theme.Spacing.l) {
            Menu {
                ForEach(years, id: \.self) { y in Button(String(y)) { year = y } }
            } label: {
                pickerLabel(year.map(String.init) ?? String(years.first ?? 0), active: year != nil, chevron: true)
            }
            Button { year = nil } label: { pickerLabel("Siempre", active: year == nil, chevron: false) }
                .buttonStyle(.plain)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
        }
    }

    private func pickerLabel(_ text: String, active: Bool, chevron: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(text.uppercased()).font(.sarrio(13, .semibold)).tracking(1.4)
                if chevron { Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(active ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            Rectangle().fill(active ? Theme.Colors.accent : .clear).frame(height: 2)
        }
        .fixedSize()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let fresh = try await api.stats(year: year)
            withAnimation(Theme.Motion.spring) { stats = fresh }
            errorMessage = nil
        } catch {
            if stats == nil { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Tu año en cifras

/// Cabecera: el desnivel en grande, que cuenta hacia arriba al entrar, y debajo km, horas, cimas y
/// salidas, con la comparación con el año anterior.
struct YearHero: View {
    let stats: UserStats
    let year: Int?
    @State private var shown: Double = 0

    var body: some View {
        let t = stats.totals
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(shown.groupedInteger)
                    .font(.sarrio(54, .bold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: shown))
                    .minimumScaleFactor(0.5)
                Text("m D+").font(.sarrio(18, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                if let prev = stats.previousTotals, prev.gain > 0 {
                    let change = (t.gain - prev.gain) / prev.gain * 100
                    Label("\(change >= 0 ? "+" : "")\(Int(change.rounded())) %", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.sarrio(14, .semibold))
                        .foregroundStyle(change >= 0 ? Theme.Colors.accent : Theme.Colors.textSecondary)
                }
            }
            Text(everestLine(t.gain))
                .font(.sarrio(14))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 0) {
                figure((t.distance / 1000).groupedInteger, "km")
                figure((t.durationS / 3600).groupedInteger, "horas")
                figure("\(t.summits)", t.summits == 1 ? "cima" : "cimas")
                figure("\(t.activities)", t.activities == 1 ? "salida" : "salidas")
            }
            .padding(.top, Theme.Spacing.s)
        }
        .onAppear { animate(to: t.gain) }
        .onChange(of: t.gain) { _, g in animate(to: g) }
    }

    private func animate(to value: Double) {
        shown = 0
        withAnimation(.easeOut(duration: 1.2)) { shown = value }
    }

    private func everestLine(_ gain: Double) -> String {
        let everests = gain / 8849
        let period = year.map { "en \($0)" } ?? "en total"
        if everests >= 1 { return "Has subido \(everests.formatted(.number.precision(.fractionLength(1)))) Everest \(period)" }
        return "El \(Int((everests * 100).rounded())) % de un Everest \(period)"
    }

    private func figure(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.sarrio(20, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary).minimumScaleFactor(0.7)
            Text(unit).font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Desnivel: acumulado | por mes

struct GainChart: View {
    let stats: UserStats
    let year: Int?
    @State private var mode = 0
    @State private var selectedDay: Int?
    @State private var selectedMonth: Int?

    private static let months = ["E", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeader(title: "Desnivel")
                if year != nil {
                    Picker("", selection: $mode) {
                        Text("Acumulado").tag(0)
                        Text("Por mes").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }
            if year != nil && stats.totals.activities == 0 {
                Text("Aún no hay salidas en \(String(year!)).")
                    .font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.vertical, Theme.Spacing.l)
            } else if year == nil {
                yearlyBars
            } else if mode == 0, let cumulative = stats.cumulative {
                cumulativeChart(cumulative)
            } else {
                monthlyBars
            }
        }
    }

    // Acumulado: tu año contra el anterior, con las líneas de Everest
    private func cumulativeChart(_ c: UserStats.Cumulative) -> some View {
        // Cada curva empieza en 0 el 1 de enero y sigue plana hasta hoy (o fin de año): con una sola
        // salida se ve un escalón, no un punto suelto que no se dibuja
        let isCurrentYear = year == Calendar.current.component(.year, from: .now)
        let today = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 365
        let current = series(c.current, until: isCurrentYear ? today : 365)
        let previous = series(c.previous, until: 365)
        let maxGain = max(current.last?.gain ?? 0, previous.last?.gain ?? 0, 100)
        // El Everest se dibuja solo si cabe (o si estás a menos del 40 % de él)
        let showsFirstEverest = maxGain >= 8849 * 0.6
        let top = max(maxGain * 1.15, showsFirstEverest ? 8849 * 1.08 : 0)
        let everests = stride(from: 8849.0, through: top, by: 8849).map { $0 }
        let value = selectedDay.flatMap { d in current.last { $0.day <= d } }
        return VStack(alignment: .leading, spacing: 6) {
            Text(value.map { "\($0.gain.groupedInteger) m · \(dayLabel($0.day))" } ?? " ")
                .font(.sarrio(13, .semibold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Chart {
                ForEach(everests, id: \.self) { e in
                    RuleMark(y: .value("Everest", e))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(e == 8849 ? "1 Everest" : "\(Int(e / 8849)) Everest")
                                .font(.sarrio(10, .medium)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                }
                ForEach(previous) { p in
                    LineMark(x: .value("Día", p.day), y: .value("m", p.gain), series: .value("Año", "anterior"))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.stepEnd)
                }
                ForEach(current) { p in
                    AreaMark(x: .value("Día", p.day), y: .value("m", p.gain))
                        .foregroundStyle(LinearGradient(colors: [Theme.Colors.accent.opacity(0.28), Theme.Colors.accent.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.stepEnd)
                    LineMark(x: .value("Día", p.day), y: .value("m", p.gain), series: .value("Año", "actual"))
                        .foregroundStyle(Theme.Colors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.stepEnd)
                }
                ForEach(c.current.indices, id: \.self) { i in
                    PointMark(x: .value("Día", Int(c.current[i][0])), y: .value("m", c.current[i][1]))
                        .foregroundStyle(Theme.Colors.accent).symbolSize(28)
                }
                if c.current.count == 1, let only = c.current.first {
                    PointMark(x: .value("Día", Int(only[0])), y: .value("m", only[1]))
                        .foregroundStyle(Theme.Colors.accent).symbolSize(60)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("\(only[1].groupedInteger) m").font(.sarrio(12, .bold)).foregroundStyle(Theme.Colors.accent)
                        }
                }
                if let value {
                    RuleMark(x: .value("Día", value.day)).foregroundStyle(Theme.Colors.textPrimary.opacity(0.25))
                    PointMark(x: .value("Día", value.day), y: .value("m", value.gain))
                        .foregroundStyle(Theme.Colors.accent).symbolSize(70)
                }
            }
            .chartXScale(domain: 1...366)
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]) { v in
                    AxisValueLabel { Text(Self.months[(v.index) % 12]).font(.sarrio(10)) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(Theme.Colors.separator)
                    AxisValueLabel { if let m = v.as(Double.self) { Text(compact(m)).font(.sarrio(10)) } }
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 220)
            HStack(spacing: Theme.Spacing.m) {
                legend(Theme.Colors.accent, year.map(String.init) ?? "")
                legend(Theme.Colors.textSecondary.opacity(0.5), year.map { String($0 - 1) } ?? "", dashed: true)
            }
        }
    }

    /// Serie para el gráfico: (1, 0), los puntos de cada salida y la última altura alargada hasta `until`.
    private func series(_ raw: [[Double]], until: Int) -> [GainPoint] {
        var out = [GainPoint(index: 0, day: 1, gain: 0)]
        for (i, p) in raw.enumerated() where p.count >= 2 {
            out.append(GainPoint(index: i + 1, day: max(1, Int(p[0])), gain: p[1]))
        }
        if let last = out.last, last.day < until {
            out.append(GainPoint(index: out.count, day: until, gain: last.gain))
        }
        return out
    }

    // Por mes: barras, el mes récord en acento y la media
    private var monthlyBars: some View {
        let months = stats.monthly
        let best = months.max { $0.gain < $1.gain }?.month
        let active = months.filter { $0.gain > 0 }
        let average = active.isEmpty ? 0 : active.map(\.gain).reduce(0, +) / Double(active.count)
        let selected = selectedMonth.flatMap { m in months.first { $0.month == m } }
        return VStack(alignment: .leading, spacing: 6) {
            Text(selected.map { "\($0.gain.groupedInteger) m · \($0.activities) \($0.activities == 1 ? "salida" : "salidas")" } ?? " ")
                .font(.sarrio(13, .semibold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Chart {
                ForEach(months) { m in
                    // Un mes con desnivel siempre se ve, aunque al lado haya uno enorme
                    BarMark(x: .value("Mes", m.month), y: .value("m", m.gain > 0 ? max(m.gain, (best.flatMap { b in months.first { $0.month == b }?.gain } ?? 0) * 0.025) : 0),
                            width: .ratio(0.62))
                        .foregroundStyle(m.month == best && m.gain > 0 ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.35))
                        .cornerRadius(3)
                }
                if average > 0 {
                    RuleMark(y: .value("Media", average))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("media \(average.groupedInteger) m").font(.sarrio(10, .medium)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                }
            }
            .chartXScale(domain: 0.5...12.5)
            .chartXAxis {
                AxisMarks(values: Array(1...12)) { v in
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Self.months[m - 1]).font(.sarrio(10)) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(Theme.Colors.separator)
                    AxisValueLabel { if let m = v.as(Double.self) { Text(compact(m)).font(.sarrio(10)) } }
                }
            }
            .chartXSelection(value: $selectedMonth)
            .frame(height: 200)
        }
    }

    // Siempre: un año por barra
    private var yearlyBars: some View {
        let best = stats.yearly.max { $0.gain < $1.gain }?.year
        return Chart(stats.yearly) { y in
            BarMark(x: .value("Año", String(y.year)), y: .value("m", y.gain), width: .ratio(0.55))
                .foregroundStyle(y.year == best ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.35))
                .cornerRadius(3)
                .annotation(position: .top) {
                    Text(compact(y.gain)).font(.sarrio(10, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                }
        }
        .chartYAxis(.hidden)
        .frame(height: 180)
    }

    private func legend(_ color: Color, _ text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 14, height: dashed ? 1.5 : 2.5)
            Text(text).font(.sarrio(11, .medium)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func compact(_ m: Double) -> String {
        m >= 1000 ? "\((m / 1000).formatted(.number.precision(.fractionLength(m >= 10_000 ? 0 : 1)))) k" : "\(Int(m))"
    }

    private func dayLabel(_ day: Int) -> String {
        var c = DateComponents()
        c.year = year ?? 2026
        c.day = day
        let date = Calendar.current.date(from: c) ?? .now
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Un punto del desnivel acumulado (día del año, metros).
struct GainPoint: Identifiable {
    var index: Int
    var day: Int
    var gain: Double
    var id: Int { index }
}
