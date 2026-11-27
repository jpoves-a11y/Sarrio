import SceneKit
import SwiftUI
import UIKit

/// «Tu cordillera 3D»: una fila por cima, de la más baja (delante) a la más alta (al fondo), cada una
/// con el perfil de la ruta con que la subiste. La más alta de cada salida, con la ruta entera; las
/// intermedias, con la subida y su espejo. El nombre de cada pico va en el eje de profundidad.
/// Se gira con el dedo, se acerca pellizcando y al tocar una fila se ve su ficha.
struct Ridge3DBlock: View {
    let peaks: [UserStats.Peak]
    @State private var selected: Int?
    @Environment(\.colorScheme) private var scheme

    private static let limit = 20

    /// Las 20 más altas, ordenadas de menor a mayor altitud (la más alta, al fondo).
    private var rows: [UserStats.Peak] {
        let withEle = peaks.filter { $0.ele != nil }
        let top = withEle.sorted { ($0.ele ?? 0) > ($1.ele ?? 0) }.prefix(Self.limit)
        return top.sorted { ($0.ele ?? 0) < ($1.ele ?? 0) }
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Tu cordillera · \(list.count) cimas")
            ZStack(alignment: .bottomTrailing) {
                Ridge3DScene(rows: list, selected: $selected, dark: scheme == .dark)
                    .frame(height: 320)
                Text("Gira con el dedo · toca una cima")
                    .font(.sarrio(10, .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(6)
            }
            if peaks.filter({ $0.ele != nil }).count > Self.limit {
                Text("Mostrando tus \(Self.limit) cimas más altas").font(.sarrio(12)).foregroundStyle(Theme.Colors.textSecondary)
            }
            if let i = selected, list.indices.contains(i) {
                card(list[i]).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Theme.Motion.spring, value: selected)
    }

    private func card(_ p: UserStats.Peak) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.sarrio(18, .bold)).foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.m) {
                    if let ele = p.ele { info("\(ele.groupedInteger) m", "altitud") }
                    if let prof = p.profile {
                        info("\((prof.distance / 1000).formatted(.number.precision(.fractionLength(1)))) km", "hasta la cima")
                        info("+\(prof.gain.groupedInteger) m", "desnivel")
                    }
                    info(p.count == 1 ? "1 vez" : "\(p.count) veces", p.profile.map { $0.date.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "")
                }
            }
            Spacer(minLength: 0)
            if let id = p.profile?.activityId {
                NavigationLink { ActivityLoaderView(activityId: id) } label: {
                    Text("Ver salida").font(.sarrio(14, .semibold)).foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    private func info(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.sarrio(14, .semibold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            Text(label).font(.sarrio(10)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// La escena 3D (SceneKit): filas de perfiles extruidos, banderillas, etiquetas y una rejilla base.
private struct Ridge3DScene: UIViewRepresentable {
    let rows: [UserStats.Peak]
    @Binding var selected: Int?
    let dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selected: $selected) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.rendersContinuously = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        let reset = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset(_:)))
        reset.numberOfTapsRequired = 2
        view.addGestureRecognizer(reset)
        tap.require(toFail: reset)
        context.coordinator.view = view
        context.coordinator.build(rows: rows, dark: dark)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.selected = $selected
        context.coordinator.build(rows: rows, dark: dark)
        context.coordinator.highlight(selected)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selected: Binding<Int?>
        weak var view: SCNView?
        private var builtKey = ""
        private var rowNodes: [SCNNode] = []
        private var cameraNode = SCNNode()
        private var shown: Int?

        private static let spacing: Float = 0.9
        private static let width: Float = 7
        private static let height: Float = 2.6

        init(selected: Binding<Int?>) { self.selected = selected }

        func build(rows: [UserStats.Peak], dark: Bool) {
            let key = rows.map { "\($0.id)" }.joined(separator: ",") + (dark ? "d" : "l")
            guard key != builtKey, let view else { return }
            builtKey = key
            shown = nil
            let scene = SCNScene()
            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            let ink = dark ? UIColor(white: 0.95, alpha: 1) : UIColor(white: 0.1, alpha: 1)
            let faint = dark ? UIColor(white: 1, alpha: 0.14) : UIColor(white: 0, alpha: 0.1)

            // Formas en metros: (distancia desde la cumbre, altitud)
            let shapes = rows.map { Self.shape(for: $0) }
            let allEle = shapes.flatMap { $0.map { $0.y } }
            let base = (allEle.min() ?? 0) - 80
            let top = max((allEle.max() ?? 1) - base, 1)
            let halfSpan = max(shapes.flatMap { $0.map { abs($0.x) } }.max() ?? 1, 500)
            let sx = Self.width / 2 / Float(halfSpan)
            let sy = Self.height / Float(top)

            rowNodes = []
            for (i, pts) in shapes.enumerated() {
                let z = -Float(i) * Self.spacing
                let row = SCNNode()
                row.name = "row-\(i)"
                row.position = SCNVector3(0, 0, z)

                // Cinta rellena bajo el perfil
                let path = UIBezierPath()
                path.move(to: CGPoint(x: CGFloat(Float(pts.first!.x) * sx), y: 0))
                for p in pts { path.addLine(to: CGPoint(x: CGFloat(Float(p.x) * sx), y: CGFloat(Float(p.y - base) * sy))) }
                path.addLine(to: CGPoint(x: CGFloat(Float(pts.last!.x) * sx), y: 0))
                path.close()
                path.flatness = 0.01
                let shape = SCNShape(path: path, extrusionDepth: 0.04)
                let t = Float(i + 1) / Float(max(rows.count, 1))
                let mat = SCNMaterial()
                mat.lightingModel = .constant
                mat.diffuse.contents = accent.withAlphaComponent(CGFloat(0.28 + 0.5 * t))
                mat.isDoubleSided = true
                mat.writesToDepthBuffer = true
                shape.materials = [mat]
                let fill = SCNNode(geometry: shape)
                fill.name = "row-\(i)"
                row.addChildNode(fill)

                // Borde superior
                let vertices = pts.map { SCNVector3(Float($0.x) * sx, Float($0.y - base) * sy, 0.025) }
                let indices: [Int32] = (0..<Int32(max(0, vertices.count - 1))).flatMap { [$0, $0 + 1] }
                let edge = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
                let edgeMat = SCNMaterial()
                edgeMat.lightingModel = .constant
                edgeMat.diffuse.contents = accent
                edge.materials = [edgeMat]
                row.addChildNode(SCNNode(geometry: edge))

                // Banderilla en la cumbre
                let summitY = Float((rows[i].ele ?? (pts.map { $0.y }.max() ?? base)) - base) * sy
                let summitX: Float = 0
                let pole = SCNCylinder(radius: 0.008, height: 0.28)
                pole.firstMaterial?.lightingModel = .constant
                pole.firstMaterial?.diffuse.contents = ink
                let poleNode = SCNNode(geometry: pole)
                poleNode.position = SCNVector3(summitX, min(summitY, Self.height) + 0.14, 0.03)
                row.addChildNode(poleNode)
                let flag = SCNPlane(width: 0.16, height: 0.1)
                flag.firstMaterial?.lightingModel = .constant
                flag.firstMaterial?.diffuse.contents = accent
                flag.firstMaterial?.isDoubleSided = true
                let flagNode = SCNNode(geometry: flag)
                flagNode.position = SCNVector3(summitX + 0.08, min(summitY, Self.height) + 0.23, 0.03)
                row.addChildNode(flagNode)

                // Nombre en el eje de profundidad, mirando siempre a la cámara
                let label = SCNText(string: "\(rows[i].name)  \(Int((rows[i].ele ?? 0).rounded())) m", extrusionDepth: 0)
                label.font = UIFont.sarrio(10, .semibold)
                label.flatness = 0.2
                label.firstMaterial?.lightingModel = .constant
                label.firstMaterial?.diffuse.contents = ink
                let labelNode = SCNNode(geometry: label)
                labelNode.scale = SCNVector3(0.018, 0.018, 0.018)
                let (minB, maxB) = labelNode.boundingBox
                labelNode.pivot = SCNMatrix4MakeTranslation(maxB.x, (minB.y + maxB.y) / 2, 0)
                labelNode.position = SCNVector3(-Self.width / 2 - 0.25, 0.08, 0)
                labelNode.constraints = [SCNBillboardConstraint()]
                row.addChildNode(labelNode)

                scene.rootNode.addChildNode(row)
                rowNodes.append(row)
            }

            // Rejilla base: eje de distancia y eje de profundidad
            let depth = Float(max(rows.count - 1, 0)) * Self.spacing
            let lines: [(SCNVector3, SCNVector3)] = [
                (SCNVector3(-Self.width / 2, 0, 0.2), SCNVector3(Self.width / 2, 0, 0.2)),
                (SCNVector3(-Self.width / 2, 0, 0.2), SCNVector3(-Self.width / 2, 0, -depth - 0.2)),
            ] + (0...max(rows.count - 1, 0)).map { i in
                let z = -Float(i) * Self.spacing
                return (SCNVector3(-Self.width / 2, 0, z), SCNVector3(Self.width / 2, 0, z))
            }
            let gridVerts = lines.flatMap { [$0.0, $0.1] }
            let gridIdx: [Int32] = Array(0..<Int32(gridVerts.count))
            let grid = SCNGeometry(sources: [SCNGeometrySource(vertices: gridVerts)],
                                   elements: [SCNGeometryElement(indices: gridIdx, primitiveType: .line)])
            grid.firstMaterial?.lightingModel = .constant
            grid.firstMaterial?.diffuse.contents = faint
            scene.rootNode.addChildNode(SCNNode(geometry: grid))

            // Cámara de tres cuartos mirando al centro de la sierra
            let center = SCNVector3(0, Self.height * 0.35, -depth / 2)
            let camera = SCNCamera()
            camera.fieldOfView = 40
            camera.zNear = 0.05
            cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(Self.width * 0.55, Self.height * 1.5 + depth * 0.15, 5.8 + depth * 0.15)
            cameraNode.look(at: center)
            scene.rootNode.addChildNode(cameraNode)

            view.scene = scene
            view.pointOfView = cameraNode
            view.defaultCameraController.target = center
        }

        /// Puntos del perfil en metros, con la cumbre en x = 0. La más alta de su salida: la ruta entera;
        /// las intermedias: la subida y su espejo. Sin ruta: un triángulo.
        static func shape(for peak: UserStats.Peak) -> [(x: Double, y: Double)] {
            guard let p = peak.profile, p.elevations.count >= 2 else {
                let ele = peak.ele ?? 0
                return [(-2000, ele - 900), (0, ele), (2000, ele - 900)]
            }
            let n = p.elevations.count
            let step = p.totalDistance / Double(n - 1)
            let s = min(max(p.summitIndex, 1), n - 1)
            if p.isRouteTop {
                return p.elevations.enumerated().map { (x: (Double($0.offset) - Double(s)) * step, y: $0.element) }
            }
            let up = Array(p.elevations[0...s])
            let down = up.dropLast().reversed()
            let pts = up + Array(down)
            return pts.enumerated().map { (x: (Double($0.offset) - Double(s)) * step, y: $0.element) }
        }

        func highlight(_ index: Int?) {
            guard index != shown else { return }
            shown = index
            let accent = UIColor(named: "AccentColor") ?? .systemOrange
            for (i, row) in rowNodes.enumerated() {
                let on = index == nil || index == i
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                row.opacity = on ? 1 : 0.25
                if let fill = row.childNodes.first?.geometry?.firstMaterial {
                    let t = CGFloat(i + 1) / CGFloat(max(rowNodes.count, 1))
                    fill.diffuse.contents = accent.withAlphaComponent(index == i ? 0.9 : 0.28 + 0.5 * t)
                }
                SCNTransaction.commit()
            }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            let index = hits.lazy.compactMap { hit -> Int? in
                var node: SCNNode? = hit.node
                while let n = node {
                    if let name = n.name, name.hasPrefix("row-"), let i = Int(name.dropFirst(4)) { return i }
                    node = n.parent
                }
                return nil
            }.first
            UISelectionFeedbackGenerator().selectionChanged()
            selected.wrappedValue = index == selected.wrappedValue ? nil : index
        }

        @objc func reset(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            view.pointOfView = cameraNode
            selected.wrappedValue = nil
        }
    }
}
