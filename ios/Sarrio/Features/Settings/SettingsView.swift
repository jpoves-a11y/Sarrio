import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if HealthKitService.isAvailable {
                    Toggle(isOn: Binding(
                        get: { library.healthConnected },
                        set: { on in
                            if on { Task { await library.connectHealth() } } else { library.disconnectHealth() }
                        }
                    )) {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                }
                SourceRow(icon: "doc", name: "Archivos GPX, FIT y TCX", status: "Disponible")
                if library.polarAvailable {
                    Toggle(isOn: Binding(
                        get: { library.polarConnected },
                        set: { on in Task { if on { await library.connectPolar() } else { await library.disconnectPolar() } } }
                    )) {
                        Label("Polar", systemImage: "dot.radiowaves.left.and.right")
                    }
                } else {
                    SourceRow(icon: "dot.radiowaves.left.and.right", name: "Polar", status: "Pendiente de activar")
                }
                SourceRow(icon: "clock", name: "Garmin · Suunto · COROS", status: "En solicitud")
            } header: {
                Text("Fuentes de datos")
            } footer: {
                Text("Con Apple Health conectado, los entrenos nuevos con GPS se suben solos, también con la app cerrada. Puedes compartir archivos a Sarrio desde cualquier app.")
            }
            Section {
                PushTestRow()
            } header: {
                Text("Notificaciones")
            } footer: {
                Text("Te avisamos cuando tus amigos hacen cima, te piden amistad o comentan tus salidas.")
            }
            Section("Apariencia") {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Tema", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }
            Section("Privacidad") {
                NavigationLink { PrivacyZonesView() } label: { Label("Zonas privadas", systemImage: "eye.slash") }
            }
            Section("Información") {
                NavigationLink { CreditsView() } label: { Label("Créditos y licencias", systemImage: "info.circle") }
            }
            Section {
                Button("Cerrar sesión") { session.signOut() }
                Button("Eliminar cuenta", role: .destructive) { confirmDelete = true }
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Ajustes")
        .task { await library.refreshProviders() }
        .confirmationDialog(
            "¿Eliminar tu cuenta?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar definitivamente", role: .destructive) {
                Task {
                    do { try await session.deleteAccount() } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("Se borrarán tu perfil, tus cumbres y tu actividad social. No se puede deshacer.")
        }
    }
}

private struct SourceRow: View {
    var icon: String
    var name: String
    var status: String

    var body: some View {
        HStack {
            Label(name, systemImage: icon)
            Spacer()
            Text(status).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Text("Datos de picos © OpenStreetMap contributors, disponibles bajo la Open Database License (ODbL).")
            Text("Mapas © Mapbox, © OpenStreetMap. Imágenes satélite de los proveedores de Mapbox.")
        }
        .navigationTitle("Créditos")
    }
}

/// «Enviar notificación de prueba»: pide permiso si hace falta, registra el iPhone y pide al
/// servidor que mande una. Enseña lo que responde Apple en palabras.
private struct PushTestRow: View {
    @Environment(\.apiClient) private var api
    @State private var sending = false
    @State private var result: String?
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await send() }
            } label: {
                HStack {
                    Label("Enviar notificación de prueba", systemImage: "bell.badge")
                    Spacer()
                    if sending { ProgressView() }
                }
            }
            .disabled(sending)
            if let result {
                Text(result)
                    .font(.sarrio(13))
                    .foregroundStyle(ok ? Theme.Colors.accent : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        result = nil
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else {
            ok = false
            result = "Las notificaciones están desactivadas para Sarrio. Actívalas en Ajustes del iPhone → Sarrio → Notificaciones."
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { await UIApplication.shared.open(url) }
            return
        }
        // Registra (o refresca) el token del iPhone antes de probar
        UIApplication.shared.registerForRemoteNotifications()
        try? await Task.sleep(for: .seconds(1.5))
        do {
            let response = try await api.pushTest()
            if response.results.isEmpty {
                ok = false
                result = "Este iPhone aún no está registrado. Vuelve a intentarlo en unos segundos."
            } else if response.results.contains(where: { $0.status == 200 }) {
                ok = true
                result = "Enviada ✓ Debería llegarte en unos segundos."
            } else {
                ok = false
                result = "Apple no la ha aceptado: " + response.results.map { Self.explain($0) }.joined(separator: "; ")
            }
        } catch APIError.http(503, _) {
            ok = false
            result = "Las notificaciones aún no están configuradas en el servidor."
        } catch {
            ok = false
            result = error.localizedDescription
        }
    }

    private static func explain(_ item: APIClient.PushTestResult.Item) -> String {
        let r = item.reason
        if r.contains("BadDeviceToken") { return "el registro del iPhone no vale para este entorno (\(item.status))" }
        if r.contains("InvalidProviderToken") { return "la clave de Apple (APNS_KEY, Key ID o Team ID) no es válida (\(item.status))" }
        if r.contains("TopicDisallowed") || r.contains("BadTopic") { return "la clave no permite enviar a esta app (\(item.status))" }
        if r.contains("ExpiredProviderToken") { return "la clave ha caducado, vuelve a intentarlo (\(item.status))" }
        return r.isEmpty ? "error \(item.status)" : "\(r) (\(item.status))"
    }
}
