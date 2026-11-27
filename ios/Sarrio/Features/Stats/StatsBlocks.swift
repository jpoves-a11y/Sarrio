import Charts
import CoreLocation
@_spi(Experimental) import MapboxMaps
import SwiftUI

// MARK: - Tu cordillera

/// Tus cimas como una sierra: de la más baja a la más alta, cada pico a su altura real, con relleno
/// degradado y la banderilla en el techo. Se recorre con el dedo para ver nombre, altitud y veces.
struct RidgeView: View {
    let peaks: [UserStats.Peak]
    @State private var selected: Int?
    @State private var drawn: CGFloat = 0

    private var sorted: [UserStats.Peak] { peaks.filter { $0.ele != nil }.sorted { ($0.ele ?? 0) < ($1.ele ?? 0) } }

    var body: some View {
        let list = sorted
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Tu cordillera · \(list.count) cimas")
            Text(selected.flatMap { i in list.indices.contains(i) ? list[i] : nil }.map { p in
                "\(p.name) · \((p.ele ?? 0).groupedInteger) m · \(p.count == 1 ? "1 vez" : "\(p.count) veces")"
            } ?? "Desliza el dedo por la sierra")
                .font(.sarrio(13, .semibold))
                .foregroundStyle(selected == nil ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
            GeometryReader { geo in
                let size = geo.size
                let points = ridge(list, size: size)
                ZStack(alignment: .topLeading) {
                    // Relleno y silueta, que crecen al aparecer
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: size.height))
                        for pt in points { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: size.width, y: size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Theme.Colors.accent.opacity(0.45), Theme.Colors.accent.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        guard let first = points.first else { return }
                        p.move(to: first)
                        for pt in points.dropFirst() { p.addLine(to: pt) }
                    }
                    .trim(from: 0, to: drawn)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Banderilla en el techo
                    if let top = summitPoint(list, size: size, index: list.count - 1) {
                        Image(uiImage: SummitFlag.image(.single, scale: 0.6, color: UIColor(named: "AccentColor") ?? .systemOrange))
                            .position(x: top.x + 8, y: top.y - 14)
                            .opacity(drawn)
                    }
                    if let i = selected, let pt = summitPoint(list, size: size, index: i) {
                        Rectangle().fill(Theme.Colors.textPrimary.opacity(0.25)).frame(width: 1, height: size.height - pt.y)
                            .position(x: pt.x, y: pt.y + (size.height - pt.y) / 2)
                        Circle().fill(Theme.Colors.surface).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.Colors.accent, lineWidth: 2.5))
                            .position(pt)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !list.isEmpty else { return }
                        let i = min(list.count - 1, max(0, Int(v.location.x / size.width * CGFloat(list.count))))
                        if i != selected { UISelectionFeedbackGenerator().selectionChanged() }
                        selected = i
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.3)) { selected = nil } })
            }
            .frame(height: 180)
            HStack {
                Text(list.first.map { "\(($0.ele ?? 0).groupedInteger) m" } ?? "").font(.sarrio(11)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(list.last.map { "\($0.name) · \(($0.ele ?? 0).groupedInteger) m" } ?? "")
                    .font(.sarrio(11, .semibold)).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 } }
    }

    /// Silueta: un pico por cima a su altura y collados entre medias, más hondos cuanto más distintos.
    private func ridge(_ list: [UserStats.Peak], size: CGSize) -> [CGPoint] {
        guard !list.isEmpty else { return [] }
        var pts: [CGPoint] = [CGPoint(x: 0, y: size.height * 0.92)]
        for i in list.indices {
            guard let top = summitPoint(list, size: size, index: i) else { continue }
            let w = size.width / CGFloat(list.count)
            // Hombro a la izquierda: algo de forma de montaña real
            pts.append(CGPoint(x: top.x - w * 0.28, y: top.y + (size.height - top.y) * 0.32))
            pts.append(top)
            if i < list.count - 1, let next = summitPoint(list, size: size, index: i + 1) {
                let col = max(top.y, next.y) + (size.height - max(top.y, next.y)) * 0.45
                pts.append(CGPoint(x: (top.x + next.x) / 2, y: col))
            }
        }
        pts.append(CGPoint(x: size.width, y: size.height * 0.85))
        return pts
    }

    private func summitPoint(_ list: [UserStats.Peak], size: CGSize, index i: Int) -> CGPoint? {
        guard list.indices.contains(i) else { return nil }
        let eles = list.compactMap(\.ele)
        let lo = (eles.min() ?? 0) * 0.85, hi = eles.max() ?? 1
        let w = size.width / CGFloat(list.count)
        let f = hi > lo ? ((list[i].ele ?? lo) - lo) / (hi - lo) : 1
        return CGPoint(x: w * (CGFloat(i) + 0.5), y: size.height - 18 - (size.height - 36) * CGFloat(f))
    }
}

// MARK: - Calendario de salidas

/// Las semanas en cuadritos (una columna por semana), más intensos cuanto más desnivel ese día.
/// Al tocar un día se abre la salida.
struct CalendarHeatmap: View {
    let calendar: UserStats.Calendar
    let streak: UserStats.Streak
    @State private var openId: ActivityLink?

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = Self.parser.date(from: calendar.start) ?? .now
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
        let byDay = Dictionary(calendar.days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let maxGain = max(1, calendar.days.map(\.gain).max() ?? 1)
        let weeks = 53

        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Calendario")
            }
            HStack(spacing: Theme.Spacing.l) {
                streakFigure("\(streak.current)", "semanas seguidas")
                streakFigure("\(streak.best)", "tu mejor racha")
            }
            GeometryReader { geo in
                let cell = min(14, (geo.size.width - CGFloat(weeks - 1) * 2) / CGFloat(weeks))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(0..<weeks, id: \.self) { w in
                            VStack(spacing: 2) {
                                ForEach(0..<7, id: \.self) { d in
                                    let date = cal.date(byAdding: .day, value: w * 7 + d, to: monday) ?? monday
                                    let key = Self.parser.string(from: date)
                                    let day = byDay[key]
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(color(day?.gain, max: maxGain, hasOuting: day != nil))
                                        .frame(width: cell, height: cell)
                                        .onTapGesture {
                                            if let id = day?.activityIds.first {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                openId = ActivityLink(id: id)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
            .frame(height: 7 * 14 + 6 * 2)
            HStack(spacing: 4) {
                Text("Menos").font(.sarrio(10)).foregroundStyle(Theme.Colors.textSecondary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(color(f * maxGain, max: maxGain, hasOuting: f > 0)).frame(width: 10, height: 10)
                }
                Text("Más desnivel").font(.sarrio(10)).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .navigationDestination(item: $openId) { link in ActivityLoaderView(activityId: link.id) }
    }

    private func color(_ gain: Double?, max: Double, hasOuting: Bool) -> Color {
        guard hasOuting else { return Theme.Colors.separator }
        let f = Swift.min(1, Swift.max(0.15, (gain ?? 0) / max))
        return Theme.Colors.accent.opacity(0.25 + 0.75 * f)
    }

    private func streakFigure(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.sarrio(22, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(label).font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct ActivityLink: Identifiable, Hashable { var id: String }

/// Abre una actividad que no está en la lista cargada (de un récord o del calendario).
struct ActivityLoaderView: View {
    let activityId: String
    @Environment(\.apiClient) private var api
    @State private var activity: Activity?
    @State private var failed = false

    var body: some View {
        Group {
            if let activity {
                ActivityDetailView(activity: activity)
            } else if failed {
                EmptyStateView(icon: "exclamationmark.triangle", title: "No se ha podido abrir", message: "Esta salida ya no está disponible.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do { activity = try await api.activity(id: activityId).activity } catch { failed = true }
        }
    }
}

// MARK: - Récords personales

struct RecordsRow: View {
    let records: UserStats.Records

    var body: some View {
        let cards = items
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Récords")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(cards, id: \.title) { card in
                            if let id = card.activityId {
                                NavigationLink { ActivityLoaderView(activityId: id) } label: { cardView(card) }
                                    .buttonStyle(.pressableCard)
                            } else {
                                cardView(card)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
    }

    private struct Item {
        var icon: String, title: String, value: String, unit: String, date: Date, activityId: String?
    }

    private var items: [Item] {
        var out: [Item] = []
        if let r = records.gain { out.append(Item(icon: "arrow.up.right", title: "Más desnivel", value: r.value.groupedInteger, unit: "m D+", date: r.date, activityId: r.activityId)) }
        if let p = records.highestPeak { out.append(Item(icon: "flag", title: "Cima más alta", value: (p.ele ?? 0).groupedInteger, unit: "m · \(p.name)", date: p.date, activityId: p.activityId)) }
        if let r = records.distance { out.append(Item(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Más larga", value: (r.value / 1000).formatted(.number.precision(.fractionLength(1))), unit: "km", date: r.date, activityId: r.activityId)) }
        if let r = records.climbRate { out.append(Item(icon: "bolt", title: "Subida más rápida", value: r.value.groupedInteger, unit: "m/h", date: r.date, activityId: r.activityId)) }
        if let r = records.duration {
            let h = Int(r.value) / 3600, m = (Int(r.value) % 3600) / 60
            out.append(Item(icon: "clock", title: "Día más largo", value: "\(h) h \(m)", unit: "min", date: r.date, activityId: r.activityId))
        }
        return out
    }

    private func cardView(_ c: Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: c.icon).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.Colors.accent)
            Text(c.title.uppercased()).font(.sarrio(10, .semibold)).tracking(1.1).foregroundStyle(Theme.Colors.textSecondary)
            Text(c.value).font(.sarrio(28, .bold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary).minimumScaleFactor(0.6)
            Text(c.unit).font(.sarrio(12, .medium)).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text(c.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.sarrio(11)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.Colors.separator, lineWidth: 0.5))
        .elevation(.low)
    }
}

// MARK: - Velocidad de subida

/// Un punto por salida (m/h) con la tendencia, y en palabras cuánto has mejorado.
struct ClimbRateChart: View {
    let points: [UserStats.ClimbRate]

    var body: some View {
        let trend = trendLine
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Velocidad de subida")
            if let sentence { Text(sentence).font(.sarrio(14, .medium)).foregroundStyle(Theme.Colors.textPrimary) }
            Chart {
                ForEach(points) { p in
                    PointMark(x: .value("Fecha", p.date), y: .value("m/h", p.value))
                        .foregroundStyle(Theme.Colors.accent)
                        .symbolSize(46)
                }
                if let trend {
                    LineMark(x: .value("Fecha", trend.0.date), y: .value("m/h", trend.0.value), series: .value("t", "tendencia"))
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    LineMark(x: .value("Fecha", trend.1.date), y: .value("m/h", trend.1.value), series: .value("t", "tendencia"))
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Theme.Colors.separator)
                    AxisValueLabel().font(.sarrio(10))
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.sarrio(10)) } }
            .frame(height: 170)
        }
    }

    /// Recta de mínimos cuadrados entre la primera y la última salida.
    private var trendLine: (UserStats.ClimbRate, UserStats.ClimbRate)? {
        guard points.count >= 3, let first = points.first, let last = points.last else { return nil }
        let xs = points.map { $0.date.timeIntervalSince1970 }, ys = points.map(\.value)
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        guard den > 0 else { return nil }
        let slope = num / den
        let f = { (x: Double) in my + slope * (x - mx) }
        return (UserStats.ClimbRate(date: first.date, value: f(xs.first!), activityId: "t0"),
                UserStats.ClimbRate(date: last.date, value: f(xs.last!), activityId: "t1"))
    }

    /// «Estás subiendo un 9 % más rápido que hace 3 meses».
    private var sentence: String? {
        let now = Date()
        let recent = points.filter { $0.date > now.addingTimeInterval(-90 * 86_400) }.map(\.value)
        let before = points.filter { $0.date <= now.addingTimeInterval(-90 * 86_400) }.map(\.value)
        guard !recent.isEmpty, !before.isEmpty else { return nil }
        let a = recent.reduce(0, +) / Double(recent.count), b = before.reduce(0, +) / Double(before.count)
        guard b > 0 else { return nil }
        let change = Int(((a - b) / b * 100).rounded())
        if change == 0 { return "Subes igual de rápido que antes" }
        return change > 0 ? "Estás subiendo un \(change) % más rápido que hace 3 meses" : "Subes un \(-change) % más despacio que hace 3 meses"
    }
}

// MARK: - Todas tus rutas

/// Todas tus rutas superpuestas en el relieve: donde más pasas, más intenso. Al tocarlo, a pantalla
/// completa para explorarlo.
struct AllRoutesBlock: View {
    @Environment(\.apiClient) private var api
    @State private var routes: [RouteLine] = []
    @State private var full = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Todas tus rutas")
            ZStack(alignment: .bottomTrailing) {
                AllRoutesMap(routes: routes, interactive: false)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                    .elevation(.medium)
                    .allowsHitTesting(false)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    .padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture { full = true }
        }
        .task { routes = (try? await api.myRoutes()) ?? [] }
        .fullScreenCover(isPresented: $full) {
            ZStack(alignment: .topTrailing) {
                AllRoutesMap(routes: routes, interactive: true).ignoresSafeArea()
                Button { full = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .environment(\.colorScheme, .dark)
                }
                .padding(Theme.Spacing.m)
            }
        }
    }
}

struct AllRoutesMap: UIViewRepresentable {
    var routes: [RouteLine]
    var interactive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero, mapInitOptions: MapInitOptions(cameraOptions: CameraOptions(center: CLLocationCoordinate2D(latitude: 42.6, longitude: 0.5), zoom: 6)))
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = interactive ? .adaptive : .hidden
        if !interactive { ReplayScene.setInteractive(false, on: mapView) }
        mapView.mapboxMap.loadStyle(.standardSatellite) { _ in
            MainActor.assumeIsolated { context.coordinator.styleLoaded(mapView) }
        }
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.update(routes, on: mapView)
    }

    @MainActor
    final class Coordinator {
        private var ready = false
        private var routes: [RouteLine] = []
        private var drawn = -1

        func styleLoaded(_ mapView: MapView) {
            let map = mapView.mapboxMap!
            for (k, v) in ["showPointOfInterestLabels": false, "showTransitLabels": false, "showRoadLabels": false] as [String: Any] {
                try? map.setStyleImportConfigProperty(for: "basemap", config: k, value: v)
            }
            ReplayScene.addTerrain(to: map, exaggeration: 1.3)
            var source = GeoJSONSource(id: "all-routes")
            source.data = .featureCollection(FeatureCollection(features: []))
            try? map.addSource(source)
            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            var glow = LineLayer(id: "all-routes-glow", source: "all-routes")
            glow.lineColor = .constant(StyleColor(accent.withAlphaComponent(0.25)))
            glow.lineWidth = .constant(9)
            glow.lineBlur = .constant(5)
            glow.lineEmissiveStrength = .constant(1)
            try? map.addLayer(glow)
            var line = LineLayer(id: "all-routes-line", source: "all-routes")
            // Translúcida: donde se solapan varias rutas, más intensa
            line.lineColor = .constant(StyleColor(accent.withAlphaComponent(0.55)))
            line.lineWidth = .constant(3)
            line.lineCap = .constant(.round)
            line.lineJoin = .constant(.round)
            line.lineEmissiveStrength = .constant(1)
            try? map.addLayer(line)
            ready = true
            drawn = -1
            update(routes, on: mapView)
        }

        func update(_ routes: [RouteLine], on mapView: MapView) {
            self.routes = routes
            guard ready, routes.count != drawn, let map = mapView.mapboxMap else { return }
            drawn = routes.count
            let lines = routes.map { r in r.points.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil } }
                .filter { $0.count >= 2 }
            let features = lines.map { Feature(geometry: .lineString(LineString($0))) }
            map.updateGeoJSONSource(withId: "all-routes", data: .featureCollection(FeatureCollection(features: features)))
            let all = lines.flatMap { $0 }
            guard all.count >= 2 else { return }
            let padding = UIEdgeInsets(top: 40, left: 30, bottom: 30, right: 30)
            if let camera = try? map.camera(for: all, camera: CameraOptions(bearing: 0, pitch: 45), coordinatesPadding: padding, maxZoom: 13, offset: nil) {
                mapView.camera.ease(to: camera, duration: 1.2)
            }
        }
    }
}
