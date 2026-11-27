import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Spacing.xl)

            HStack(alignment: .center, spacing: 12) {
                Image("SarrioMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 52)
                Image("Wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sarrio")
            .padding(.bottom, Theme.Spacing.xl)

            Text("Cada cumbre,\nen un solo lugar.")
                .font(.sarrio(36, .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.bottom, Theme.Spacing.m)

            Text("Sarrio detecta los picos que subes y construye tu biblioteca de montaña.")
                .font(.sarrio(17))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xl)

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                FeatureRow(icon: "applewatch", title: "Sincroniza tus salidas",
                           text: "Apple Health, Polar o tus archivos GPX.")
                FeatureRow(icon: "cube.transparent", title: "Revívelas en 3D",
                           text: "Tu ruta sobre el relieve, en satélite.")
                FeatureRow(icon: "person.2", title: "Comparte con tus amigos",
                           text: "Emblemas, retos, likes y comentarios.")
            }

            Spacer()

            SignInWithAppleButton(.continue) { request in
                MainActor.assumeIsolated { session.prepare(request) }
            } onCompletion: { result in
                Task { await session.handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            Text("Al continuar aceptas los Términos y la Política de privacidad.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.m)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
        .background(Theme.Colors.background)
        .alert("No se pudo iniciar sesión", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

private struct FeatureRow: View {
    var icon: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarrio(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(text).font(.sarrio(15)).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
