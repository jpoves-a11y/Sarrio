import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Sarrio").font(.largeTitle.bold())
            Text("Tu biblioteca de cumbres. Sincroniza tus salidas, revive cada ascensión en 3D y compártelas con tus amigos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            // Fase 2: SignInWithAppleButton → POST /v1/auth/apple
            Button("Continuar (modo desarrollo)") { session.continueAsGuest() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
