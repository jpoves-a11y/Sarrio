import CoreLocation
import MapboxMaps
import UIKit

/// La banderilla de cumbre: mástil metálico con remate dorado, paño con volumen que ondea (dos ondas,
/// sombreado por tiras según hacia dónde mira la tela), manguito al mástil, hito de piedras en la
/// base y sombra proyectada. El mismo dibujo en todos los mapas.
///
/// Coordenadas: el pie del mástil en (0, 0), hacia arriba negativo. `s` escala todo (1 = tamaño normal).
enum SummitFlag {
    struct ClothPoint { var x, top, bottom, shade: CGFloat }

    /// Medidas a escala `s`.
    static func size(_ s: CGFloat) -> (pole: CGFloat, width: CGFloat, height: CGFloat) { (40 * s, 26 * s, 15 * s) }

    /// El paño en `N` tiras para el instante `t` (segundos) con un desfase `phase` (cada bandera el suyo).
    static func cloth(width w: CGFloat, height ch: CGFloat, t: Double, phase: Double) -> [ClothPoint] {
        let n = 30, theta = 0.42
        return (0...n).map { i in
            let u = Double(i) / Double(n)
            let a = (0.05 + 0.30 * u) * Double(ch)
            let k1 = 2 * Double.pi * 1.15, k2 = 2 * Double.pi * 2.6
            let z = a * sin(k1 * u - 5.6 * t + phase) + 0.28 * a * sin(k2 * u - 9.1 * t + phase * 1.7)
            let dz = (a * k1 * cos(k1 * u - 5.6 * t + phase) + 0.28 * a * k2 * cos(k2 * u - 9.1 * t + phase * 1.7)) / Double(w)
            let x = u * Double(w) * cos(theta) + z * sin(theta) * 0.9
            let sag = 0.13 * Double(ch) * u * u
            let flutter = 0.05 * Double(ch) * u * sin(2 * Double.pi * 2 * u - 7 * t + phase)
            let top = sag + flutter + z * 0.12
            let bottom = Double(ch) * (1 - 0.08 * u) + sag * 1.35 + flutter * 0.6 + z * 0.10
            // Luz desde arriba a la izquierda: la tela que mira al sol se aclara
            let light = max(0, (dz * 0.55 + 0.84) / sqrt(dz * dz + 1))
            return ClothPoint(x: CGFloat(x), top: CGFloat(top), bottom: CGFloat(bottom), shade: CGFloat(0.48 + 0.62 * light))
        }
    }

    /// Estado de la animación de clavarse (`plant` 0…1): caída desde arriba, golpe y rebote.
    static func plantPose(_ plant: Double, scale s: CGFloat) -> (drop: CGFloat, tilt: CGFloat) {
        let drop: Double = plant < 0.55 ? -(1 - pow(plant / 0.55, 2)) * 420 : 0
        let sink: Double = plant >= 0.55 ? sin((plant - 0.55) / 0.45 * .pi * 1.6) * exp(-(plant - 0.55) * 6) * 3 * Double(s) : 0
        let tilt: Double = plant >= 0.55 ? sin((plant - 0.55) / 0.45 * .pi * 2.2) * exp(-(plant - 0.55) * 5) * 7 : 0
        return (CGFloat(drop + sink), CGFloat(tilt * .pi / 180))
    }

    // MARK: Dibujo

    /// Sombra proyectada, hito de piedras y polvo del golpe (lo que no cae con la bandera).
    static func drawGround(in ctx: CGContext, scale s: CGFloat, t: Double, phase: Double, plant: Double) {
        let (h, w, ch) = size(s)
        let shadowAlpha = min(1, plant * 1.6)
        if shadowAlpha > 0 {
            // Sombra: mástil y paño cizallados hacia la derecha y aplastados en el suelo
            let pts = cloth(width: w, height: ch, t: t, phase: phase)
            let sx: CGFloat = 0.9, sy: CGFloat = 0.22
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: h * sx, y: -h * sy))
            for p in pts { path.addLine(to: CGPoint(x: (h - p.top) * sx + p.x * 0.95, y: -(h - p.top) * sy)) }
            for p in pts.reversed() { path.addLine(to: CGPoint(x: (h - p.bottom) * sx + p.x * 0.95, y: -(h - p.bottom) * sy)) }
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 2.2 * s, color: UIColor.black.withAlphaComponent(0.34 * shadowAlpha).cgColor)
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.30 * shadowAlpha).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
        // Polvo del golpe
        if plant > 0.5 && plant < 0.85 {
            let k = CGFloat((plant - 0.5) / 0.35)
            ctx.setFillColor(UIColor(red: 0.89, green: 0.86, blue: 0.80, alpha: 0.7 * (1 - k)).cgColor)
            for dir in [-1.0, 1.0] as [CGFloat] {
                for j in 0..<4 {
                    let r = (1.8 - CGFloat(j) * 0.35) * s
                    let x = dir * (4 + CGFloat(j) * 3 + k * 12) * s
                    let y = -(0.5 + CGFloat(j) * 1.1 + k * 3) * s
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
        }
        // Hito de piedras
        guard shadowAlpha > 0 else { return }
        let stones: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-4.5, 0.2, 3.2, 2.1, 0.55), (3.8, 0.4, 3.4, 2.2, 0.49), (-0.6, -1.1, 3.6, 2.4, 0.61), (-2.6, -2.9, 2.6, 1.8, 0.66), (2.2, -2.6, 2.4, 1.7, 0.56),
        ]
        let k = s * 0.55
        ctx.setAlpha(shadowAlpha)
        for (x, y, rx, ry, g) in stones {
            ctx.setFillColor(UIColor(white: g, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: (x - rx) * k, y: (y - ry) * k, width: 2 * rx * k, height: 2 * ry * k))
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            ctx.fillEllipse(in: CGRect(x: (x - 0.6 - rx * 0.5) * k, y: (y - 0.6 - ry * 0.35) * k, width: rx * k, height: ry * 0.7 * k))
        }
        ctx.setAlpha(1)
    }

    /// Mástil, paño, manguito y remate (lo que cae al clavarse).
    static func drawFlag(in ctx: CGContext, scale s: CGFloat, t: Double, phase: Double, color: UIColor) {
        let (h, w, ch) = size(s)
        let space = CGColorSpaceCreateDeviceRGB()

        // Mástil metálico (cilindro: oscuro en los bordes, brillo en el centro)
        let pole = CGRect(x: -0.85 * s, y: -h, width: 1.7 * s, height: h)
        ctx.saveGState()
        ctx.addPath(UIBezierPath(roundedRect: pole, cornerRadius: 0.85 * s).cgPath)
        ctx.clip()
        let metal = CGGradient(colorsSpace: space, colors: [
            UIColor(white: 0.17, alpha: 1).cgColor, UIColor(white: 0.62, alpha: 1).cgColor, UIColor(white: 0.92, alpha: 1).cgColor,
            UIColor(white: 0.49, alpha: 1).cgColor, UIColor(white: 0.13, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.35, 0.5, 0.68, 1])!
        ctx.drawLinearGradient(metal, start: CGPoint(x: pole.minX, y: 0), end: CGPoint(x: pole.maxX, y: 0), options: [])
        ctx.restoreGState()

        // Paño en tiras sombreadas
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let pts = cloth(width: w, height: ch, t: t, phase: phase)
        let x0 = 1.0 * s, y0 = -h + 1.5 * s
        for i in 0..<(pts.count - 1) {
            let p = pts[i], q = pts[i + 1], k = (p.shade + q.shade) / 2
            ctx.setFillColor(UIColor(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: 1).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x0 + p.x, y: y0 + p.top))
            ctx.addLine(to: CGPoint(x: x0 + q.x + 0.35, y: y0 + q.top))
            ctx.addLine(to: CGPoint(x: x0 + q.x + 0.35, y: y0 + q.bottom))
            ctx.addLine(to: CGPoint(x: x0 + p.x, y: y0 + p.bottom))
            ctx.closePath()
            ctx.fillPath()
        }
        // Contorno sutil del paño
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: x0 + pts[0].x, y: y0 + pts[0].top))
        for p in pts { outline.addLine(to: CGPoint(x: x0 + p.x, y: y0 + p.top)) }
        for p in pts.reversed() { outline.addLine(to: CGPoint(x: x0 + p.x, y: y0 + p.bottom)) }
        outline.closeSubpath()
        ctx.addPath(outline)
        ctx.setStrokeColor(UIColor(red: 0.27, green: 0.09, blue: 0.02, alpha: 0.35).cgColor)
        ctx.setLineWidth(0.45 * s)
        ctx.strokePath()

        // Manguito: la tela enrollada al mástil
        let sleeve = CGRect(x: -0.2 * s, y: y0 + pts[0].top - 0.3 * s, width: 2.4 * s, height: pts[0].bottom - pts[0].top + 0.6 * s)
        ctx.saveGState()
        ctx.addPath(UIBezierPath(roundedRect: sleeve, cornerRadius: 0.9 * s).cgPath)
        ctx.clip()
        ctx.setFillColor(UIColor(red: r * 0.62, green: g * 0.62, blue: b * 0.62, alpha: 1).cgColor)
        ctx.fill(sleeve)
        let sleeveShade = CGGradient(colorsSpace: space, colors: [
            UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.black.withAlphaComponent(0.3).cgColor,
        ] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(sleeveShade, start: CGPoint(x: sleeve.minX, y: 0), end: CGPoint(x: sleeve.maxX, y: 0), options: [])
        ctx.restoreGState()

        // Remate dorado
        let ball = CGRect(x: -1.6 * s, y: -h - 2.5 * s, width: 3.2 * s, height: 3.2 * s)
        ctx.saveGState()
        ctx.addEllipse(in: ball)
        ctx.clip()
        let gold = CGGradient(colorsSpace: space, colors: [
            UIColor(red: 1, green: 0.96, blue: 0.81, alpha: 1).cgColor, UIColor(red: 0.88, green: 0.70, blue: 0.29, alpha: 1).cgColor,
            UIColor(red: 0.48, green: 0.33, blue: 0.08, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(gold, startCenter: CGPoint(x: ball.minX + ball.width * 0.35, y: ball.minY + ball.height * 0.3), startRadius: 0,
                               endCenter: CGPoint(x: ball.midX, y: ball.midY), endRadius: ball.width * 0.7, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: Imágenes fijas (capas de símbolos del globo)

    enum Style { case single, group }

    /// Imagen con el pie del mástil centrado abajo (para `iconAnchor .bottom`).
    static func image(_ style: Style, scale s: CGFloat = 1, color: UIColor, t: Double = 0.35, phase: Double = 0) -> UIImage {
        let (h, w, _) = size(s)
        let half = max(w + 14 * s, h * 0.9 + w) // lo que ocupa a la derecha (paño y sombra)
        let size = CGSize(width: half * 2, height: h + 6 * s)
        return UIGraphicsImageRenderer(size: size).image { r in
            let ctx = r.cgContext
            let draw: (CGFloat, CGFloat, Double) -> Void = { dx, k, extra in
                ctx.saveGState()
                ctx.translateBy(x: half + dx, y: size.height - 2 * s)
                SummitFlag.drawGround(in: ctx, scale: s * k, t: t, phase: phase + extra, plant: 1)
                SummitFlag.drawFlag(in: ctx, scale: s * k, t: t, phase: phase + extra, color: color)
                ctx.restoreGState()
            }
            switch style {
            case .single:
                draw(0, 1, 0)
            case .group:
                draw(-9 * s, 0.8, 1.7)
                draw(9 * s, 0.86, 3.1)
                draw(0, 1, 0)
            }
        }
    }
}

/// La banderilla como vista para las *view annotations* de Mapbox: ondea sin parar y se clava
/// (cae desde arriba, golpe con polvo, rebote y toque háptico) con `plant()`.
final class SummitFlagView: UIView {
    private let scale: CGFloat
    private let color: UIColor
    private let phase = Double.random(in: 0...(2 * .pi))
    private let ground = FlagCanvas()
    private let flag = FlagCanvas()
    private let label = UILabel()
    private var link: CADisplayLink?
    private var start = CACurrentMediaTime()
    private var plant: Double = 1
    private var plantStart: CFTimeInterval?
    private var impacted = false
    /// Dónde está el pie del mástil dentro de la vista (para anclarla al punto).
    let footX: CGFloat
    private let fixedSize: CGSize

    init(name: String?, elevation: Double?, scale: CGFloat = 1, color: UIColor = UIColor(named: "AccentColor") ?? .systemOrange, planted: Bool = true) {
        self.scale = scale
        self.color = color
        let (h, w, _) = SummitFlag.size(scale)
        footX = 26 * scale // margen a la izquierda para el polvo del golpe
        // Texto a la derecha del paño
        let text = NSMutableAttributedString()
        if let name {
            text.append(NSAttributedString(string: name, attributes: [.font: UIFont.sarrio(13 * min(1.3, max(0.9, scale)), .semibold), .foregroundColor: UIColor.white]))
        }
        if let elevation {
            text.append(NSAttributedString(string: (name == nil ? "" : "\n") + "\(Int(elevation.rounded()).formatted()) m",
                                           attributes: [.font: UIFont.sarrio(12 * min(1.3, max(0.9, scale)), .medium).monospacedDigits,
                                                        .foregroundColor: UIColor.white.withAlphaComponent(0.85)]))
        }
        label.attributedText = text
        label.numberOfLines = 2
        let labelSize = text.length > 0 ? label.sizeThatFits(CGSize(width: 220, height: 60)) : .zero
        let flagWidth = footX + max(w + 6 * scale, h * 0.9 + w * 0.95)
        fixedSize = CGSize(width: flagWidth + (labelSize.width > 0 ? labelSize.width + 6 : 0), height: h + 6 * scale)
        super.init(frame: CGRect(origin: .zero, size: fixedSize))
        isUserInteractionEnabled = false
        clipsToBounds = false

        for canvas in [ground, flag] {
            canvas.frame = bounds
            canvas.isOpaque = false
            canvas.backgroundColor = .clear
            canvas.clipsToBounds = false
            canvas.layer.masksToBounds = false
            addSubview(canvas)
        }
        ground.draws = { [unowned self] ctx in
            ctx.translateBy(x: footX, y: fixedSize.height - 2 * scale)
            SummitFlag.drawGround(in: ctx, scale: scale, t: time, phase: phase, plant: plant)
        }
        flag.draws = { [unowned self] ctx in
            ctx.translateBy(x: footX, y: fixedSize.height - 2 * scale)
            SummitFlag.drawFlag(in: ctx, scale: scale, t: time, phase: phase, color: color)
        }
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.6
        label.layer.shadowRadius = 2.5
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.frame = CGRect(x: footX + w + 8 * scale, y: max(0, fixedSize.height - h - 2), width: labelSize.width, height: labelSize.height)
        addSubview(label)

        if !planted { setUnplanted() }
        startLink()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var time: Double { CACurrentMediaTime() - start }

    /// Escondida arriba, a la espera de `plant()`.
    func setUnplanted() {
        plant = 0
        applyPose()
    }

    /// Cae desde arriba, se clava con un golpe de polvo, rebota y se queda ondeando.
    func plant(delay: TimeInterval = 0) {
        plant = 0
        impacted = false
        applyPose()
        plantStart = CACurrentMediaTime() + delay
    }

    private func startLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { link?.invalidate(); link = nil } else if link == nil { startLink() }
    }

    @objc private func tick() {
        if let begin = plantStart {
            let k = (CACurrentMediaTime() - begin) / 1.1
            if k >= 0 {
                plant = min(1, k)
                if plant >= 0.55 && !impacted {
                    impacted = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                if plant >= 1 { plantStart = nil }
                applyPose()
            }
        }
        ground.setNeedsDisplay()
        flag.setNeedsDisplay()
    }

    private func applyPose() {
        let pose = SummitFlag.plantPose(plant, scale: scale)
        let foot = CGPoint(x: footX - bounds.midX, y: fixedSize.height - 2 * scale - bounds.midY)
        // Gira alrededor del pie y cae en vertical
        var t = CGAffineTransform(translationX: foot.x, y: foot.y)
        t = t.rotated(by: pose.tilt)
        t = t.translatedBy(x: -foot.x, y: -foot.y)
        flag.transform = t.concatenating(CGAffineTransform(translationX: 0, y: pose.drop))
        flag.alpha = plant <= 0 ? 0 : 1
        label.alpha = CGFloat(max(0, (plant - 0.7) / 0.3))
    }

    override var intrinsicContentSize: CGSize { fixedSize }
    override func sizeThatFits(_ size: CGSize) -> CGSize { fixedSize }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize { fixedSize }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize { fixedSize }
}

/// Lienzo que dibuja con un cierre (sin recortar: la sombra y la caída salen de sus límites).
final class FlagCanvas: UIView {
    var draws: ((CGContext) -> Void)?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        draws?(ctx)
    }
}

extension SummitFlagView {
    /// La anotación de Mapbox con el pie del mástil justo sobre la cima.
    func annotation(at coordinate: CLLocationCoordinate2D) -> ViewAnnotation {
        let annotation = ViewAnnotation(coordinate: coordinate, view: self)
        // Esquina inferior izquierda en el punto, desplazada para que el pie (no la esquina) caiga en él
        annotation.variableAnchors = [ViewAnnotationAnchorConfig(anchor: .bottomLeft, offsetX: -footX)]
        annotation.allowOverlap = true
        return annotation
    }
}
