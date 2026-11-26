import CoreLocation
import Foundation
import WeatherKit

/// Una hora del tiempo que hizo durante la actividad.
struct ReplayWeatherHour: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case dry, rain, snow }

    let date: Date
    let kind: Kind
    /// mm caídos en la hora.
    let amount: Double
    /// Espesor de la niebla: 0 nada … 1 densa.
    var fog: Double = 0

    var showsSomething: Bool { kind != .dry || fog > 0 }
}

/// El tiempo de la actividad (Apple Weather). Vacío si no se sabe.
struct ReplayWeather: Equatable, Sendable {
    var hours: [ReplayWeatherHour] = []
    /// Página legal de Apple Weather: su atribución es obligatoria donde se muestren sus datos.
    var legalURL: URL?

    /// El tiempo a la hora `date`, si llovió, nevó o hubo niebla.
    func hour(at date: Date) -> ReplayWeatherHour? {
        guard let hour = hours.last(where: { $0.date <= date }) ?? hours.first,
              abs(hour.date.timeIntervalSince(date)) < 2 * 3600 else { return nil }
        return hour.showsSomething ? hour : nil
    }

    var hasWeather: Bool { hours.contains { $0.showsSomething } }
}

/// Carga el tiempo histórico por horas de WeatherKit (disponible desde agosto de 2021), una vez por
/// actividad. Como en KM2.
@MainActor
enum ReplayWeatherLoader {
    private static var cache: [String: ReplayWeather] = [:]
    private static let historyStart = Date(timeIntervalSince1970: 1_627_776_000)

    static func load(activityId: String, center: CLLocationCoordinate2D, start: Date, end: Date) async -> ReplayWeather {
        if let cached = cache[activityId] { return cached }
        guard start > historyStart, CLLocationCoordinate2DIsValid(center) else { return ReplayWeather() }
        var weather = ReplayWeather()
        do {
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let hours = try await WeatherService.shared.weather(
                for: location,
                including: .hourly(startDate: start.addingTimeInterval(-3600), endDate: max(end, start).addingTimeInterval(3600))
            )
            weather.hours = hours.map { hour in
                let amount = hour.precipitationAmount.converted(to: .millimeters).value
                let kind: ReplayWeatherHour.Kind
                switch hour.precipitation {
                case .snow, .sleet, .mixed: kind = .snow
                case .rain, .hail: kind = .rain
                default: kind = .dry
                }
                return ReplayWeatherHour(date: hour.date, kind: amount >= 0.1 ? kind : .dry, amount: amount, fog: fog(in: hour))
            }
            if weather.hasWeather {
                weather.legalURL = try? await WeatherService.shared.attribution.legalPageURL
            }
        } catch {
            return ReplayWeather()
        }
        if !Task.isCancelled { cache[activityId] = weather }
        return weather
    }

    /// Niebla: Apple Weather la llama así, o apenas se ve. La calima y el humo no cuentan.
    private static func fog(in hour: HourWeather) -> Double {
        let metres = hour.visibility.converted(to: .meters).value
        if hour.condition == .foggy { return metres < 200 ? 1 : (metres < 600 ? 0.85 : 0.7) }
        if hour.precipitation == .none, hour.humidity >= 0.92, metres > 0, metres < 3000 { return metres < 1000 ? 0.7 : 0.4 }
        return 0
    }
}
