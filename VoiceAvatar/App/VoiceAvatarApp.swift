import SwiftUI

@main
struct VoiceAvatarApp: App {
    @StateObject private var profileManager = VoiceProfileManager()
    @StateObject private var authService = BiometricAuthService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.requiresAuthentication {
                    LockScreenView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(profileManager)
            .environmentObject(authService)
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            authService.checkAuthenticationTimeout()
        case .inactive:
            break
        case .background:
            if authService.isAuthenticationEnabled {
                authService.logout()
            }
        @unknown default:
            break
        }
    }
}
