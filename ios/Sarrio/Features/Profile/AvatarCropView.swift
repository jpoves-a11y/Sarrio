import SwiftUI
import UIKit

/// Recorte de la foto de perfil: la imagen a pantalla completa bajo una máscara circular. Se
/// pellizca para ampliar y se arrastra para encuadrar; el círculo nunca queda con huecos.
/// «Usar» devuelve un JPEG cuadrado de 512 px.
struct AvatarCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onDone: (Data) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 48
            let base = baseSize(for: side)
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .frame(width: base.width * scale, height: base.height * scale)
                    .offset(offset)
                // Velo con un agujero circular
                Rectangle()
                    .fill(.black.opacity(0.6))
                    .mask {
                        Rectangle()
                            .overlay(Circle().frame(width: side, height: side).blendMode(.destinationOut))
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 1)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(maxScale, max(1, lastScale * value.magnification))
                            offset = clamp(offset, side: side, base: base)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            lastOffset = offset
                        },
                    DragGesture()
                        .onChanged { value in
                            let proposed = CGSize(width: lastOffset.width + value.translation.width,
                                                  height: lastOffset.height + value.translation.height)
                            offset = clamp(proposed, side: side, base: base)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
            )
            .overlay(alignment: .bottom) {
                HStack {
                    Button("Cancelar", action: onCancel)
                        .font(.sarrio(17, .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Mueve y amplía")
                        .font(.sarrio(13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Usar") {
                        if let data = render(side: side, base: base) { onDone(data) }
                    }
                    .font(.sarrio(17, .bold))
                    .foregroundStyle(Theme.Colors.accent)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
            }
        }
        .statusBarHidden()
    }

    /// Tamaño de la imagen a escala 1: cubre justo el círculo por su lado corto.
    private func baseSize(for side: CGFloat) -> CGSize {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return CGSize(width: side, height: side) }
        let k = side / min(w, h)
        return CGSize(width: w * k, height: h * k)
    }

    /// Que la imagen siempre cubra el círculo (sin bordes vacíos).
    private func clamp(_ o: CGSize, side: CGFloat, base: CGSize) -> CGSize {
        let maxX = max(0, (base.width * scale - side) / 2)
        let maxY = max(0, (base.height * scale - side) / 2)
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    /// Lo que queda dentro del círculo, a 512 × 512 en JPEG.
    private func render(side: CGFloat, base: CGSize) -> Data? {
        let output: CGFloat = 512
        let k = output / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format)
        let picture = renderer.image { _ in
            let w = base.width * scale * k, h = base.height * scale * k
            let x = (output - w) / 2 + offset.width * k
            let y = (output - h) / 2 + offset.height * k
            image.draw(in: CGRect(x: x, y: y, width: w, height: h))
        }
        return picture.jpegData(compressionQuality: 0.8)
    }
}
