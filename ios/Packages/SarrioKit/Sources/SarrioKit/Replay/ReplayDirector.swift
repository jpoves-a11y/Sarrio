import Foundation

/// Dónde está la cámara.
public struct ReplayCamera: Sendable, Equatable {
    public var center: GeoPoint
    /// Metros desde el centro.
    public var distance: Double
    public var pitch: Double
    /// Grados, sin normalizar (para que los giros se interpolen por el lado corto).
    public var heading: Double

    public init(center: GeoPoint, distance: Double, pitch: Double, heading: Double) {
        self.center = center; self.distance = distance; self.pitch = pitch; self.heading = heading
    }

    /// De `a` a `b`: posición suavizada, distancia en escala logarítmica (un zoom natural) y la
    /// inclinación más tarde en el movimiento.
    public static func interpolate(_ a: ReplayCamera, _ b: ReplayCamera, _ t: Double) -> ReplayCamera {
        let u = min(1, max(0, t))
        // Smootherstep: sin tirón en ningún extremo
        let eased = u * u * u * (u * (u * 6 - 15) + 10)
        let pitchT = min(1, max(0, (u - 0.35) / 0.65))
        let pitchEased = pitchT * pitchT * (3 - 2 * pitchT)
        return ReplayCamera(
            center: GeoPoint(lat: a.center.lat + (b.center.lat - a.center.lat) * eased,
                             lon: a.center.lon + (b.center.lon - a.center.lon) * eased),
            distance: exp(log(max(1, a.distance)) + (log(max(1, b.distance)) - log(max(1, a.distance))) * eased),
            pitch: a.pitch + (b.pitch - a.pitch) * pitchEased,
            heading: a.heading + shortestTurn(from: a.heading, to: b.heading) * eased
        )
    }

    /// Grados con signo para girar de `from` a `to` por el lado corto (-180...180).
    public static func shortestTurn(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

/// Tiempos y cámaras de un replay: vista lejana → vuelo hasta el inicio → seguir al montañero →
/// mostrar toda la ruta → giro lento. Los tiempos son los del replay de KM2; en Sarrio la marcha
/// se frena al pasar por cada cumbre, y la cámara va más inclinada para que se lea el relieve.
public struct ReplayTimeline: Sendable {
    public let plan: ReplayPlan
    /// Multiplica lo que tarda la subida (0,6 rápido, 1 normal, 1,5 lento).
    public var speed: Double

    /// Segundos: la vista lejana se mantiene y luego vuela hasta el inicio.
    public let introHold: Double = 0.8
    public let flyIn: Double = 4.2
    /// En el inicio antes de echar a andar.
    public let startHold: Double = 0.8
    public let finish: Double = 3.4
    /// Giro lento alrededor de toda la ruta tras la llegada.
    public let orbit: Double = 14

    /// Cuánto más despacio se pasa por una cumbre (en el punto más alto, 3 veces más lento).
    static let summitSlowdown = 2.0
    /// En la cumbre más alta, más aún (6 veces más lento cerca de ella)…
    static let topSummitSlowdown = 5.0
    /// …y una parada en la cima para ver cómo se clava la bandera (segundos).
    public static let topSummitDwell = 1.8

    /// Metros hasta la cumbre más alta de la actividad (la de mayor altitud en la ruta), si hay cumbres.
    public var topSummitDistance: Double? { Self.topSummit(of: plan) }

    static func topSummit(of plan: ReplayPlan) -> Double? {
        plan.summitDistances.max { a, b in elevation(plan, at: a) < elevation(plan, at: b) }
    }

    private static func elevation(_ plan: ReplayPlan, at distance: Double) -> Double {
        var low = 0, high = plan.cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if plan.cumulative[mid] <= distance { low = mid } else { high = mid }
        }
        return plan.elevations[low] ?? plan.elevations[high] ?? -.infinity
    }

    /// Pesos acumulados de la distancia (frenada en cumbres), para invertir el avance.
    private let warpDistances: [Double]
    private let warpWeights: [Double]

    public init(plan: ReplayPlan, speed: Double = 1) {
        self.plan = plan
        self.speed = speed
        // Densidad de tiempo: 1 en general, más alrededor de cada cumbre (una campana de ±σ)
        let sigma = max(60, plan.length * 0.012)
        let top = Self.topSummit(of: plan)
        let samples = 400
        var distances: [Double] = []
        var weights: [Double] = [0]
        distances.reserveCapacity(samples + 1)
        for k in 0...samples {
            let d = plan.length * Double(k) / Double(samples)
            distances.append(d)
            if k > 0 {
                let mid = (d + distances[k - 1]) / 2
                let bump = plan.summitDistances.reduce(0) { $0 + exp(-pow(mid - $1, 2) / (2 * sigma * sigma)) }
                var density = 1 + Self.summitSlowdown * min(1, bump)
                if let top {
                    density += (Self.topSummitSlowdown - Self.summitSlowdown) * exp(-pow(mid - top, 2) / (2 * sigma * sigma))
                }
                weights.append(weights[k - 1] + density * (d - distances[k - 1]))
            }
        }
        // La parada en la cima más alta: un tramo de «tiempo» en el que casi no se avanza
        if let top, let base = weights.last, base > 0 {
            let run = min(32, max(14, 10 + plan.length / 1000 * 1.6)) * min(2, max(0.4, speed))
            let f = min(0.25, Self.topSummitDwell / run)
            let dwell = base * f / (1 - f)
            let k = min(samples, max(1, Int((top / max(1, plan.length) * Double(samples)).rounded(.up))))
            for j in k...samples { weights[j] += dwell }
        }
        warpDistances = distances
        warpWeights = weights
    }

    /// Las rutas largas duran más: 14 s una corta, hasta 32 s.
    public var run: Double { min(32, max(14, 10 + plan.length / 1000 * 1.6)) * min(2, max(0.4, speed)) }
    public var runStart: Double { introHold + flyIn + startHold }
    public var runEnd: Double { runStart + run }
    public var total: Double { runEnd + finish }

    /// Metros recorridos tras `time` segundos de marcha: arranque y parada suaves, ritmo constante
    /// entre medias, y más despacio al coronar.
    public func distance(atRunTime time: Double) -> Double {
        let u = min(1, max(0, time / run))
        let ramp = 0.16
        let top = 1 / (1 - ramp)
        let eased: Double
        if u < ramp { eased = 0.5 * top / ramp * u * u } else if u > 1 - ramp { eased = 1 - 0.5 * top / ramp * (1 - u) * (1 - u) } else { eased = top * (u - ramp / 2) }
        return warp(min(1, max(0, eased)))
    }

    /// Fracción de «tiempo de marcha» → metros, con la frenada en las cumbres.
    private func warp(_ fraction: Double) -> Double {
        guard let total = warpWeights.last, total > 0 else { return plan.length * fraction }
        let target = fraction * total
        var low = 0, high = warpWeights.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if warpWeights[mid] <= target { low = mid } else { high = mid }
        }
        let span = warpWeights[high] - warpWeights[low]
        let f = span > 0 ? (target - warpWeights[low]) / span : 0
        return warpDistances[low] + (warpDistances[high] - warpDistances[low]) * f
    }

    /// Metros recorridos a los `elapsed` segundos del replay.
    public func distance(atElapsed elapsed: Double) -> Double {
        if elapsed <= runStart { return 0 }
        if elapsed >= runEnd { return plan.length }
        return distance(atRunTime: elapsed - runStart)
    }

    /// Suavizado de la cámara que sigue (segundos, cada una de sus dos etapas).
    public var cameraEasing: Double { min(0.2, max(0.1, 120 / max(1, plan.length / run))) }

    /// A cuántos metros está la cámara que sigue del punto que mira.
    public var followDistance: Double { min(3600, max(1400, plan.length * 0.16)) }

    public func followCamera(at distance: Double, heading: Double) -> ReplayCamera {
        ReplayCamera(center: plan.cameraCoordinate(at: distance), distance: followDistance, pitch: 58, heading: heading)
    }

    /// Lejos, centrada en la ruta: donde empieza el replay.
    public var overviewCamera: ReplayCamera {
        ReplayCamera(center: plan.center, distance: max(revealDistance * 6, 15_000), pitch: 0, heading: 0)
    }

    private var revealDistance: Double { max(1600, plan.extent * 3.1) }

    /// Toda la ruta a la vista, inclinada para ver el relieve.
    public func revealCamera(heading: Double) -> ReplayCamera {
        ReplayCamera(center: plan.center, distance: revealDistance, pitch: 52, heading: heading)
    }
}

/// Un instante del replay: la cámara, el montañero y cuánta ruta está dibujada.
public struct ReplayFrame: Sendable {
    public var camera: ReplayCamera
    /// Metros recorridos.
    public var run: Double
    public var hiker: GeoPoint
    /// Metros de ruta dibujados: hasta el montañero; toda la ruta al llegar.
    public var trail: Double
    /// Cumbres ya coronadas (índices en `plan.summitDistances`).
    public var summitsReached: Int
    public var showsHiker: Bool
    /// Ha llegado: toda la ruta dibujada.
    public var isRevealed: Bool
    /// Ha terminado la fase final: toda la ruta a la vista (sigue el giro lento).
    public var isFinished: Bool
    /// Ya no se mueve nada.
    public var isOver: Bool
}

/// Calcula el replay fotograma a fotograma para cualquier reloj (el de la pantalla, o uno fijo para
/// un vídeo). Guarda el estado suavizado de la cámara: el rumbo y el centro en dos etapas
/// (un deslizamiento con amortiguamiento crítico). Mismo algoritmo que KM2.
public struct ReplayDirector: Sendable {
    public let timeline: ReplayTimeline
    private var heading: Double
    private var finishHeading: Double
    private var cameraCenterStage: GeoPoint
    private var cameraCenter: GeoPoint
    private var lastFollowCamera: ReplayCamera?

    public init(timeline: ReplayTimeline) {
        self.timeline = timeline
        heading = timeline.plan.cameraBearing(at: 0)
        finishHeading = heading
        cameraCenter = timeline.plan.cameraCoordinate(at: 0)
        cameraCenterStage = cameraCenter
    }

    /// Cuándo deja de moverse todo: tras el giro lento.
    public var end: Double { timeline.total + timeline.orbit }

    /// El fotograma a los `elapsed` segundos, `dt` segundos después del anterior.
    public mutating func frame(at elapsed: Double, dt: Double) -> ReplayFrame {
        let plan = timeline.plan
        let run = timeline.distance(atElapsed: elapsed)
        let hiker = plan.coordinate(at: run)

        // Rumbo: hacia donde va la ruta suavizada, suavizado (constante de tiempo 1,4 s, como mucho 24°/s)
        if elapsed > timeline.introHold + timeline.flyIn * 0.5 && elapsed < timeline.runEnd {
            var turn = ReplayCamera.shortestTurn(from: heading, to: plan.cameraBearing(at: run)) * (1 - exp(-dt / 1.4))
            let maxTurn = 24 * dt
            turn = min(maxTurn, max(-maxTurn, turn))
            heading += turn
            finishHeading = heading
        }
        // Centro: la ruta suavizada en dos etapas (su velocidad cambia sin tirones en las curvas),
        // apuntando a donde estará el montañero tras el retardo del suavizado, y nunca a más del 12 %
        // de la distancia de la cámara: el montañero no puede salirse del encuadre
        if elapsed >= timeline.runStart && elapsed < timeline.runEnd {
            let easing = timeline.cameraEasing
            let target = plan.cameraCoordinate(at: timeline.distance(atElapsed: elapsed + 2 * easing))
            let k = 1 - exp(-dt / easing)
            cameraCenterStage = GeoPoint(lat: cameraCenterStage.lat + (target.lat - cameraCenterStage.lat) * k,
                                         lon: cameraCenterStage.lon + (target.lon - cameraCenterStage.lon) * k)
            cameraCenter = GeoPoint(lat: cameraCenter.lat + (cameraCenterStage.lat - cameraCenter.lat) * k,
                                    lon: cameraCenter.lon + (cameraCenterStage.lon - cameraCenter.lon) * k)
            cameraCenter = Self.limit(cameraCenter, within: timeline.followDistance * 0.12, of: hiker)
        }

        let camera: ReplayCamera
        if elapsed < timeline.introHold {
            camera = timeline.overviewCamera
        } else if elapsed < timeline.introHold + timeline.flyIn {
            let t = (elapsed - timeline.introHold) / timeline.flyIn
            camera = ReplayCamera.interpolate(timeline.overviewCamera, timeline.followCamera(at: 0, heading: heading), t)
        } else if elapsed < timeline.runStart {
            camera = timeline.followCamera(at: 0, heading: heading)
        } else if elapsed < timeline.runEnd {
            var follow = timeline.followCamera(at: run, heading: heading)
            follow.center = cameraCenter
            lastFollowCamera = follow
            camera = follow
        } else if elapsed < timeline.total {
            let t = (elapsed - timeline.runEnd) / timeline.finish
            let from = lastFollowCamera ?? timeline.followCamera(at: plan.length, heading: finishHeading)
            camera = ReplayCamera.interpolate(from, timeline.revealCamera(heading: finishHeading + 20), t)
        } else {
            // Giro lento alrededor de la ruta: desde parado hasta 5°/s en 3 s
            let t = min(elapsed, end) - timeline.total
            let turned = t < 3 ? 5 * t * t / 6 : 5 * (t - 1.5)
            camera = timeline.revealCamera(heading: finishHeading + 20 + turned)
        }

        let revealed = elapsed >= timeline.runEnd
        return ReplayFrame(
            camera: camera,
            run: run,
            hiker: hiker,
            trail: revealed ? plan.length : run,
            summitsReached: plan.summitDistances.filter { $0 <= run + 1 }.count,
            showsHiker: run > 0 && run < plan.length,
            isRevealed: revealed,
            isFinished: elapsed >= timeline.total,
            isOver: elapsed >= end
        )
    }

    /// Las cámaras por las que pasa el replay, para cargar el mapa antes de reproducirlo: una vista
    /// cada medio nivel de zoom, cada 15° de inclinación, cada 20° de giro y, en marcha, cada cuarto
    /// de la distancia de la cámara a lo largo de la ruta (como mucho ~60), más la última.
    public static func preloadCameras(for timeline: ReplayTimeline, until: Double? = nil) -> [ReplayCamera] {
        var director = ReplayDirector(timeline: timeline)
        let end = min(director.end, until ?? director.end)
        let spacing = max(timeline.followDistance * 0.25, timeline.plan.length / 60)
        let halfZoom = log(1.4)
        let step = 1.0 / 30
        var cameras: [ReplayCamera] = []
        var taken: ReplayCamera?
        var takenRun = 0.0
        var current: ReplayCamera?
        var elapsed = 0.0, previous = 0.0
        while elapsed <= end {
            let frame = director.frame(at: elapsed, dt: elapsed - previous)
            previous = elapsed
            let camera = frame.camera
            current = camera
            var take = true
            if let taken {
                let zoomed = abs(log(max(1, camera.distance) / max(1, taken.distance))) >= halfZoom
                let tilted = abs(camera.pitch - taken.pitch) >= 15
                let turned = abs(ReplayCamera.shortestTurn(from: taken.heading, to: camera.heading)) >= 20
                let walked = elapsed > timeline.runStart && elapsed < timeline.runEnd && frame.run - takenRun >= spacing
                take = zoomed || tilted || turned || walked
            }
            if take {
                cameras.append(camera)
                taken = camera
                takenRun = frame.run
            }
            elapsed += step
        }
        if let current { cameras.append(current) }
        return cameras
    }

    /// El arranque, cargado lo último antes de reproducir: el vuelo y los primeros 5 s de marcha, y
    /// luego la primera vista (la que hay en pantalla cuando se quita la cortina).
    public static func startCameras(for timeline: ReplayTimeline) -> [ReplayCamera] {
        preloadCameras(for: timeline, until: timeline.runStart + 5) + [timeline.overviewCamera]
    }

    private static func limit(_ center: GeoPoint, within maxMeters: Double, of hiker: GeoPoint) -> GeoPoint {
        let kx = cos(hiker.lat * .pi / 180) * 111_320, ky = 110_574.0
        let dx = (center.lon - hiker.lon) * kx, dy = (center.lat - hiker.lat) * ky
        let offset = hypot(dx, dy)
        guard offset > maxMeters, offset > 0 else { return center }
        let f = maxMeters / offset
        return GeoPoint(lat: hiker.lat + (center.lat - hiker.lat) * f, lon: hiker.lon + (center.lon - hiker.lon) * f)
    }
}

/// Dónde está el sol (ecuaciones de posición solar de la NOAA), para la luz del mapa en el momento
/// de la actividad. Mismo cálculo que KM2.
public enum SunPosition {
    /// Elevación del sol sobre el horizonte (grados; negativa bajo él).
    public static func elevation(at point: GeoPoint, date: Date) -> Double {
        let r = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525
        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = meanAnomaly * r
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let omega = (125.04 - 1934.136 * t) * r
        let longitude = (meanLongitude + center - 0.00569 - 0.00478 * sin(omega)) * r
        let obliquity0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (obliquity0 + 0.00256 * cos(omega)) * r
        let declination = asin(sin(obliquity) * sin(longitude))
        let y = pow(tan(obliquity / 2), 2)
        let l0 = meanLongitude * r
        let equationOfTime = 4 / r * (y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))
        let minutes = (julianDay + 0.5).truncatingRemainder(dividingBy: 1) * 1440
        var trueSolarTime = (minutes + equationOfTime + 4 * point.lon).truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }
        let latitude = point.lat * r
        let cosZenith = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle * r)
        return 90 - acos(min(1, max(-1, cosZenith))) / r
    }

    /// Luz de Mapbox Standard: día por encima de 6°, noche por debajo de −6° y, entre medias,
    /// amanecer si sube o atardecer si baja.
    public static func lightPreset(at point: GeoPoint, date: Date) -> String {
        let now = elevation(at: point, date: date)
        if now > 6 { return "day" }
        if now < -6 { return "night" }
        return elevation(at: point, date: date.addingTimeInterval(600)) > now ? "dawn" : "dusk"
    }
}
