import SwiftUI

@main
struct VoiceAvatarApp: App {
    @StateObject private var profileManager = VoiceProfileManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileManager)
        }
    }
}
