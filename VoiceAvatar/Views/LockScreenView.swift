import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var authService: BiometricAuthService
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.backgroundPrimary, .accentPurple.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                appIcon

                titleSection

                Spacer()

                unlockButton

                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
        .alert("Authentifizierung fehlgeschlagen", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            if authService.biometricType != .none {
                Button("Mit Code entsperren") {
                    authenticateWithFallback()
                }
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            authenticate()
        }
    }

    private var appIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.accentPurple, .accentPurpleLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: .accentPurple.opacity(0.4), radius: 20, y: 10)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
        }
    }

    private var titleSection: some View {
        VStack(spacing: 12) {
            Text("VoiceAvatar")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Deine Stimmprofile sind geschützt")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.successGreen)
                Text("Verschlüsselt & Gesichert")
                    .font(.caption)
                    .foregroundColor(.successGreen)
            }
            .padding(.top, 8)
        }
    }

    private var unlockButton: some View {
        VStack(spacing: 16) {
            Button(action: { authenticate() }) {
                HStack(spacing: 12) {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: authService.biometricType.iconName)
                            .font(.title2)
                    }

                    Text(isAuthenticating ? "Authentifiziere..." : "Entsperren mit \(authService.biometricType.displayName)")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentPurple)
                .cornerRadius(16)
            }
            .disabled(isAuthenticating)

            if authService.biometricType == .none {
                Button(action: { authenticateWithFallback() }) {
                    Text("Mit Gerätecode entsperren")
                        .font(.subheadline)
                        .foregroundColor(.accentPurple)
                }
            }
        }
        .padding(.horizontal)
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        Task {
            do {
                try await authService.authenticate()
            } catch let error as AuthenticationError {
                if case .cancelled = error {
                    // User cancelled, don't show error
                } else {
                    errorMessage = error.localizedDescription ?? "Unbekannter Fehler"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAuthenticating = false
        }
    }

    private func authenticateWithFallback() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        Task {
            do {
                try await authService.authenticateWithFallback()
            } catch let error as AuthenticationError {
                if case .cancelled = error {
                    // User cancelled, don't show error
                } else {
                    errorMessage = error.localizedDescription ?? "Unbekannter Fehler"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAuthenticating = false
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(BiometricAuthService())
}
