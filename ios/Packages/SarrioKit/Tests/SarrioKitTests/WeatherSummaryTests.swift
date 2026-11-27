import Foundation
import XCTest
@testable import SarrioKit

final class WeatherSummaryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func hour(_ i: Int, _ sky: WeatherSummary.Sky, _ temp: Double, wind: Double = 10, gust: Double? = nil) -> WeatherSummary.Hour {
        WeatherSummary.Hour(start: t0.addingTimeInterval(Double(i) * 3600), sky: sky, temperature: temp, wind: wind, gust: gust)
    }

    func testSharesAreWeightedByMinutesInside() {
        // Salida de 0:40 a 2:40: 20 min de la hora 0 (sol), 60 de la 1 (nublado), 40 de la 2 (lluvia)
        let hours = [hour(0, .sunny, 8), hour(1, .cloudy, 10, wind: 20, gust: 35), hour(2, .rain, 9), hour(3, .snow, 2)]
        let s = WeatherSummary(hours: hours, from: t0.addingTimeInterval(40 * 60), to: t0.addingTimeInterval(160 * 60))!
        XCTAssertEqual(s.shares[.sunny] ?? 0, 20.0 / 120, accuracy: 0.001)
        XCTAssertEqual(s.shares[.cloudy] ?? 0, 60.0 / 120, accuracy: 0.001)
        XCTAssertEqual(s.shares[.rain] ?? 0, 40.0 / 120, accuracy: 0.001)
        XCTAssertNil(s.shares[.snow])
        XCTAssertEqual(s.minTemperature, 8)
        XCTAssertEqual(s.maxTemperature, 10)
        XCTAssertEqual(s.maxWind, 20)
        XCTAssertEqual(s.maxGust, 35)
        XCTAssertEqual(s.significant.map { $0.sky }, [.cloudy, .rain, .sunny])
    }

    func testSummitHourAndNoData() {
        let hours = [hour(0, .sunny, 8), hour(1, .cloudy, 5)]
        let s = WeatherSummary(hours: hours, from: t0, to: t0.addingTimeInterval(7200), summitAt: t0.addingTimeInterval(5400))!
        XCTAssertEqual(s.atSummit?.temperature, 5)
        XCTAssertNil(WeatherSummary(hours: hours, from: t0.addingTimeInterval(-90000), to: t0.addingTimeInterval(-86400)))
    }
}
