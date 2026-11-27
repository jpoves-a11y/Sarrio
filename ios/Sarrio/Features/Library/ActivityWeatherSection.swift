import CoreLocation
import SarrioKit
import SwiftUI
import WeatherKit

/// «El tiempo» de una salida: el reparto (soleado, nublado, niebla, lluvia, nieve) en una barra,
/// la temperatura y el viento, y el tiempo en la cima. Compacto; desaparece si no hay datos.
struct ActivityWeatherSection: View {
    let activityId: String
    let center: CLLocationCoordinate2D
    let start: Date
    let end: Date
    var summit: (name: String, at: Date)?

    @State private var summary: WeatherSummary?
    @State private var legalURL: URL?

    var body: some View {
        Group {
            if let summary {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: "El tiempo")
                    bar(summary)
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(summary.significant, id: \.sky) { item in
                            Label("\(Int((item.share * 100).rounded())) %", systemImage: Self.icon(item.sky))
                                .font(.sarrio(13, .semibold).monospacedDigit())
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityLabel("\(Self.title(item.sky)) \(Int((item.share * 100).rounded())) por ciento")
                        }
                    }
                    Text(line(summary))
                        .font(.sarrio(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summit, let h = summary.atSummit {
                        Label("En \(summit.name): \(Int(h.temperature.rounded())) °C, \(Self.title(h.sky).lowercased())", systemImage: "flag")
                            .font(.sarrio(14, .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    if let legalURL {
                        Link(destination: legalURL) {
                            Label("Datos: Apple Weather", systemImage: "apple.logo")
                                .font(.sarrio(11, .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .task(id: activityId) {
            let loaded = await ActivityWeatherLoader.load(activityId: activityId, center: center, start: start, end: end, summitAt: summit?.at)
            withAnimation(Theme.Motion.spring) {
                summary = loaded.summary
                legalURL = loaded.legalURL
            }
        }
    }

    /// Barra apilada, de más a menos.
    private func bar(_ s: WeatherSummary) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(s.significant, id: \.sky) { item in
                    Rectangle()
                        .fill(Self.color(item.sky))
                        .frame(width: max(4, (geo.size.width - CGFloat(s.significant.count - 1) * 2) * CGFloat(item.share)))
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func line(_ s: WeatherSummary) -> String {
        let tMin = Int(s.minTemperature.rounded()), tMax = Int(s.maxTemperature.rounded())
        let temp = tMin == tMax ? "\(tMin) °C" : "\(tMin) – \(tMax) °C"
        var wind = "viento hasta \(Int(s.maxWind.rounded())) km/h"
        if let g = s.maxGust, g > s.maxWind + 5 { wind += " (rachas \(Int(g.rounded())))" }
        return "\(temp) · \(wind)"
    }

    static func icon(_ sky: WeatherSummary.Sky) -> String {
        switch sky {
        case .sunny: "sun.max"
        case .cloudy: "cloud"
        case .fog: "cloud.fog"
        case .rain: "cloud.rain"
        case .snow: "snowflake"
        }
    }

    static func title(_ sky: WeatherSummary.Sky) -> String {
        switch sky {
        case .sunny: "Soleado"
        case .cloudy: "Nublado"
        case .fog: "Niebla"
        case .rain: "Lluvia"
        case .snow: "Nieve"
        }
    }

    static func color(_ sky: WeatherSummary.Sky) -> Color {
        switch sky {
        case .sunny: Color(red: 0.98, green: 0.74, blue: 0.24)
        case .cloudy: Color(red: 0.62, green: 0.65, blue: 0.70)
        case .fog: Color(red: 0.78, green: 0.79, blue: 0.81)
        case .rain: Color(red: 0.30, green: 0.56, blue: 0.85)
        case .snow: Color(red: 0.62, green: 0.82, blue: 0.95)
        }
    }
}

/// Tiempo histórico por horas de WeatherKit (desde agosto de 2021), resumido. Uno por actividad.
@MainActor
enum ActivityWeatherLoader {
    private static var cache: [String: (summary: WeatherSummary?, legalURL: URL?)] = [:]
    private static let historyStart = Date(timeIntervalSince1970: 1_627_776_000)

    static func load(activityId: String, center: CLLocationCoordinate2D, start: Date, end: Date, summitAt: Date?) async
        -> (summary: WeatherSummary?, legalURL: URL?) {
        if let cached = cache[activityId] { return cached }
        guard start > historyStart, CLLocationCoordinate2DIsValid(center) else { return (nil, nil) }
        do {
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let forecast = try await WeatherService.shared.weather(
                for: location,
                including: .hourly(startDate: start.addingTimeInterval(-3600), endDate: max(end, start).addingTimeInterval(3600))
            )
            let hours = forecast.map { h in
                WeatherSummary.Hour(
                    start: h.date,
                    sky: sky(h.condition),
                    temperature: h.temperature.converted(to: .celsius).value,
                    wind: h.wind.speed.converted(to: .kilometersPerHour).value,
                    gust: h.wind.gust?.converted(to: .kilometersPerHour).value
                )
            }
            let summary = WeatherSummary(hours: hours, from: start, to: end, summitAt: summitAt)
            let legal = summary == nil ? nil : try? await WeatherService.shared.attribution.legalPageURL
            let result = (summary: summary, legalURL: legal)
            if !Task.isCancelled { cache[activityId] = result }
            return result
        } catch {
            return (nil, nil)
        }
    }

    /// Estado de Apple Weather → soleado, nublado, niebla, lluvia o nieve.
    private static func sky(_ c: WeatherCondition) -> WeatherSummary.Sky {
        switch c {
        case .clear, .mostlyClear, .hot, .sunShowers, .sunFlurries: .sunny
        case .foggy, .haze, .smoky, .blowingDust: .fog
        case .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms,
             .tropicalStorm, .hurricane: .rain
        case .snow, .heavySnow, .flurries, .blowingSnow, .blizzard, .sleet, .freezingDrizzle, .freezingRain, .hail, .wintryMix, .frigid: .snow
        default: .cloudy
        }
    }
}
