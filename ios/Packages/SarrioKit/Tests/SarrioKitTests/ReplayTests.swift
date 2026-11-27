import Foundation
import Testing
@testable import SarrioKit

/// Una subida en zigzag de ~6 km hacia el norte, con la cima a mitad de camino.
private func zigzagTrack() -> [TrackPoint] {
    (0..<600).map { i in
        let t = Double(i)
        return TrackPoint(latitude: 42.60 + t * 0.00009, longitude: 0.65 + sin(t / 25) * 0.002,
                          elevation: 1800 + 1500 * sin(.pi * t / 599), time: Date(timeIntervalSince1970: 1_784_000_000 + t * 30))
    }
}

@Suite struct ReplayPlanTests {
    @Test func measuresAndSmoothsTheRoute() throws {
        let plan = try #require(ReplayPlan(track: zigzagTrack()))
        #expect(plan.points.count <= ReplayPlan.maxPoints + 1)
        #expect(plan.length > 5_000 && plan.length < 9_000)
        #expect(plan.cumulative.last == plan.length)
        #expect(plan.extent > 500)
        let top = try #require(plan.elevation(at: plan.length / 2))
        #expect(abs(top - 3300) < 30)
        #expect(plan.elevationGain(upTo: plan.length) > 1400)
    }

    @Test func placesSummitsAlongTheRoute() throws {
        let track = zigzagTrack()
        let summit = GeoPoint(lat: track[300].latitude, lon: track[300].longitude)
        let plan = try #require(ReplayPlan(track: track, summits: [summit]))
        #expect(plan.summitDistances.count == 1)
        #expect(abs(plan.summitDistances[0] - plan.length / 2) < plan.length * 0.05)
    }

    @Test func removesGPSKnots() {
        // Recta con un nudo de vueltas pequeñas a mitad (una parada)
        var track = (0..<50).map { TrackPoint(latitude: 42 + Double($0) * 0.0001, longitude: 0) }
        let stop = track[25]
        let knot = (0..<20).map { k in
            TrackPoint(latitude: stop.latitude + 0.00006 * cos(Double(k)), longitude: 0.00008 * sin(Double(k)))
        }
        track.insert(contentsOf: knot, at: 26)
        let cleaned = ReplayPlan.withoutKnots(track)
        #expect(cleaned.count < track.count - 10)
        #expect(cleaned.last == track.last)
    }

    @Test func rejectsDegenerateRoutes() {
        #expect(ReplayPlan(track: [TrackPoint(latitude: 42, longitude: 0)]) == nil)
        #expect(ReplayPlan(track: [TrackPoint(latitude: 0, longitude: 0), TrackPoint(latitude: 0, longitude: 0)]) == nil)
    }
}

@Suite struct ReplayTimelineTests {
    @Test func phasesFollowKM2Timings() throws {
        let timeline = ReplayTimeline(plan: try #require(ReplayPlan(track: zigzagTrack())))
        #expect(timeline.runStart == 0.8 + 4.2 + 0.8)
        #expect(timeline.run >= 14 && timeline.run <= 32)
        #expect(timeline.distance(atElapsed: 0) == 0)
        #expect(timeline.distance(atElapsed: timeline.runEnd + 1) == timeline.plan.length)
        // Avance monótono
        var last = 0.0
        for k in 0...200 {
            let d = timeline.distance(atRunTime: timeline.run * Double(k) / 200)
            #expect(d >= last - 1e-6)
            last = d
        }
        #expect(abs(last - timeline.plan.length) < 1e-6)
    }

    @Test func slowsDownAtSummits() throws {
        let track = zigzagTrack()
        let summit = GeoPoint(lat: track[300].latitude, lon: track[300].longitude)
        let plain = ReplayTimeline(plan: try #require(ReplayPlan(track: track)))
        let withSummit = ReplayTimeline(plan: try #require(ReplayPlan(track: track, summits: [summit])))
        // Tiempo que se pasa en los 200 m alrededor de la cima
        func timeNear(_ timeline: ReplayTimeline, _ center: Double) -> Double {
            var inside = 0.0
            let steps = 4000
            for k in 0..<steps {
                let d = timeline.distance(atRunTime: timeline.run * Double(k) / Double(steps))
                if abs(d - center) < 100 { inside += timeline.run / Double(steps) }
            }
            return inside
        }
        let center = withSummit.plan.summitDistances[0]
        #expect(timeNear(withSummit, center) > 1.8 * timeNear(plain, center))
    }
}

@Suite struct TopSummitTests {
    @Test func slowsDownAndStopsAtTheHighestSummit() throws {
        let track = zigzagTrack()
        // Dos cumbres: una a 1/4 (más baja) y la más alta a mitad
        let low = GeoPoint(lat: track[150].latitude, lon: track[150].longitude)
        let high = GeoPoint(lat: track[300].latitude, lon: track[300].longitude)
        let timeline = ReplayTimeline(plan: try #require(ReplayPlan(track: track, summits: [low, high])))
        let top = try #require(timeline.topSummitDistance)
        #expect(abs(top - timeline.plan.summitDistances[1]) < 1)
        func timeNear(_ center: Double, _ radius: Double) -> Double {
            var inside = 0.0
            let steps = 8000
            for k in 0..<steps {
                let d = timeline.distance(atRunTime: timeline.run * Double(k) / Double(steps))
                if abs(d - center) < radius { inside += timeline.run / Double(steps) }
            }
            return inside
        }
        // Más tiempo junto a la más alta que junto a la otra, y una parada de verdad en la cima
        #expect(timeNear(top, 100) > 2 * timeNear(timeline.plan.summitDistances[0], 100))
        #expect(timeNear(top, 30) > ReplayTimeline.topSummitDwell * 0.7)
    }
}

@Suite struct ReplayDirectorTests {
    @Test func cameraGlidesWithoutJumpsAndKeepsTheHikerInFrame() throws {
        let track = zigzagTrack()
        let plan = try #require(ReplayPlan(track: track, summits: [GeoPoint(lat: track[300].latitude, lon: track[300].longitude)]))
        var director = ReplayDirector(timeline: ReplayTimeline(plan: plan))
        let timeline = director.timeline
        let dt = 1.0 / 60
        var previous: ReplayFrame?
        var elapsed = 0.0
        var reachedSummit = false
        while elapsed <= director.end + dt {
            let frame = director.frame(at: elapsed, dt: dt)
            if elapsed > timeline.runStart + 0.5 && elapsed < timeline.runEnd {
                let offset = Geo.distance(frame.camera.center.lat, frame.camera.center.lon, frame.hiker.lat, frame.hiker.lon)
                #expect(offset <= timeline.followDistance * 0.12 + 1)
                if let previous {
                    // Nunca gira más de 24°/s
                    #expect(abs(ReplayCamera.shortestTurn(from: previous.camera.heading, to: frame.camera.heading)) <= 24 * dt + 1e-6)
                }
            }
            if frame.summitsReached == 1 { reachedSummit = true }
            previous = frame
            elapsed += dt
        }
        #expect(reachedSummit)
        #expect(previous?.isOver == true)
        #expect(previous?.trail == plan.length)
    }

    @Test func interpolatesZoomInLogScaleAndTurnsTheShortWay() {
        let a = ReplayCamera(center: GeoPoint(lat: 0, lon: 0), distance: 100, pitch: 0, heading: 350)
        let b = ReplayCamera(center: GeoPoint(lat: 1, lon: 1), distance: 10_000, pitch: 60, heading: 10)
        let mid = ReplayCamera.interpolate(a, b, 0.5)
        #expect(abs(mid.distance - 1000) < 1)
        #expect(abs(mid.heading - 360) < 1e-9)
        #expect(mid.pitch < 30) // la inclinación llega más tarde
        #expect(ReplayCamera.interpolate(a, b, 1).center == b.center)
    }

    @Test func preloadsAReasonableNumberOfViews() throws {
        let timeline = ReplayTimeline(plan: try #require(ReplayPlan(track: zigzagTrack())))
        let cameras = ReplayDirector.preloadCameras(for: timeline)
        #expect(cameras.count > 10 && cameras.count < 160)
        #expect(ReplayDirector.startCameras(for: timeline).last == timeline.overviewCamera)
    }
}

@Suite struct SunPositionTests {
    private let aneto = GeoPoint(lat: 42.6311, lon: 0.6569)

    @Test func highAtSummerNoonAndBelowTheHorizonAtNight() {
        // 21-06-2026 a las 12:00 UTC (mediodía solar aprox.) y a las 23:00 UTC
        let noon = Date(timeIntervalSince1970: 1_782_043_200)
        let night = Date(timeIntervalSince1970: 1_782_082_800)
        #expect(SunPosition.elevation(at: aneto, date: noon) > 65)
        #expect(SunPosition.elevation(at: aneto, date: night) < -10)
        #expect(SunPosition.lightPreset(at: aneto, date: noon) == "day")
        #expect(SunPosition.lightPreset(at: aneto, date: night) == "night")
    }
}
