import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// «Compartir → Sarrio» desde Archivos, Mail, Garmin Connect, WhatsApp…
/// Copia los GPX/FIT/TCX a la bandeja del App Group; la app los procesa al abrirse.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.receive(providers) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum State { case working, done(Int), failed(String) }
    var state: State = .working

    private static let types = ["com.topografix.gpx", "com.garmin.fit", "com.garmin.tcx", UTType.xml.identifier, UTType.data.identifier]

    func receive(_ providers: [NSItemProvider]) async {
        var saved = 0
        for provider in providers {
            guard let type = Self.types.first(where: provider.hasItemConformingToTypeIdentifier) else { continue }
            if await copy(provider, type: type) { saved += 1 }
        }
        state = saved > 0 ? .done(saved) : .failed("Sarrio solo puede importar archivos GPX, FIT y TCX.")
    }

    private func copy(_ provider: NSItemProvider, type: String) async -> Bool {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                // El archivo temporal solo existe dentro de este bloque: se copia aquí mismo.
                guard let url, SharedInbox.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: (try? SharedInbox.add(fileAt: url)) != nil)
            }
        }
    }
}

private struct ShareCard: View {
    var model: ShareModel
    var close: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                icon
                Text(title).font(.sarrio(20, .semibold)).multilineTextAlignment(.center)
                Text(message).font(.sarrio(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(action: close) {
                    Text("Hecho").font(.sarrio(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
                }
                .disabled(isWorking)
                .opacity(isWorking ? 0.4 : 1)
            }
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.18), radius: 34, y: 20)
            .padding(16)
            .offset(y: appeared ? 0 : 400)
        }
        .preferredColorScheme(.light)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true } }
        .sensoryFeedback(.success, trigger: isDone)
    }

    private var isWorking: Bool { if case .working = model.state { true } else { false } }
    private var isDone: Bool { if case .done = model.state { true } else { false } }

    @ViewBuilder private var icon: some View {
        ZStack {
            Rectangle().fill(Color.accentColor.opacity(0.08)).frame(width: 64, height: 2).offset(y: 34)
            if isWorking {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: isDone ? "mountain.2.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isDone ? Color.accentColor : .orange)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isWorking)
    }

    private var title: String {
        switch model.state {
        case .working: "Guardando…"
        case let .done(n): n == 1 ? "Actividad añadida" : "\(n) actividades añadidas"
        case .failed: "No se pudo añadir"
        }
    }

    private var message: String {
        switch model.state {
        case .working: "Un momento."
        case .done: "Abre Sarrio y buscaremos las cumbres que subiste."
        case let .failed(reason): reason
        }
    }
}
