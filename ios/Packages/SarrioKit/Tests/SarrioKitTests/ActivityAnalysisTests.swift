import Foundation
import XCTest
@testable import SarrioKit

final class ActivityAnalysisTests: XCTestCase {
    /// Recta hacia el norte: `n` puntos cada `step` m, subiendo `rise` m por punto, cada `dt` s.
    private func line(n: Int, step: Double, rise: Double, dt: Double?, from ele: Double = 1000) -> [TrackPoint] {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<n).map { i in
            TrackPoint(latitude: 42 + Double(i) * step / 111_195, longitude: 0.5, elevation: ele + Double(i) * rise,
                       time: dt.map { t0.addingTimeInterval(Double(i) * $0) })
        }
    }

    func testSlopesAndHardestSection() {
        // 2 km llanos y luego 1 km al 25 %
        let flat = line(n: 41, step: 50, rise: 0, dt: nil)
        let steep = line(n: 21, step: 50, rise: 12.5, dt: nil).dropFirst().map {
            TrackPoint(latitude: $0.latitude + 2000 / 111_195, longitude: $0.longitude, elevation: $0.elevation, time: nil)
        }
        let a = ActivityAnalysis(points: flat + steep)
        XCTAssertEqual(a.buckets.flat, 2000, accuracy: 60)
        XCTAssertEqual(a.buckets.hard, 1000, accuracy: 60)
        XCTAssertEqual(a.hardest?.grade ?? 0, 25, accuracy: 0.5)
        XCTAssertFalse(a.hasTimes)
        XCTAssertNil(a.bestClimb15)
        XCTAssertEqual(a.splits.map(\.km), [1, 2, 3])
        XCTAssertNil(a.splits[0].seconds)
    }

    func testClimbRateSplitsAndMovingTime() {
        // 3 km subiendo 600 m en 1 h (600 m/h), un punto cada 50 m y 60 s
        let up = line(n: 61, step: 50, rise: 10, dt: 60)
        let a = ActivityAnalysis(points: up)
        XCTAssertTrue(a.hasTimes)
        XCTAssertEqual(a.bestClimb15 ?? 0, 600, accuracy: 1)
        XCTAssertTrue(a.rates.allSatisfy { abs($0.rate - 600) < 1 })
        XCTAssertEqual(a.splits.count, 3)
        XCTAssertEqual(a.splits[0].seconds ?? 0, 1200, accuracy: 1)
        XCTAssertEqual(a.splits[0].gain, 200, accuracy: 1)
        XCTAssertEqual(a.movingSeconds ?? 0, 3600, accuracy: 1)
        XCTAssertEqual(a.stoppedSeconds ?? 1, 0, accuracy: 1)
    }

    func testStopsCountAsStopped() {
        var pts = line(n: 11, step: 50, rise: 0, dt: 30)
        let last = pts.last!
        // Parado 10 min en el mismo sitio
        pts.append(TrackPoint(latitude: last.latitude, longitude: last.longitude, elevation: last.elevation, time: last.time!.addingTimeInterval(600)))
        let a = ActivityAnalysis(points: pts)
        XCTAssertEqual(a.movingSeconds ?? 0, 300, accuracy: 1)
        XCTAssertEqual(a.stoppedSeconds ?? 0, 600, accuracy: 1)
    }
}
