import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            ProfileListView()
                .tabItem {
                    Label("Profile", systemImage: "person.wave.2.fill")
                }
                .tag(1)

            VoiceConversionView()
                .tabItem {
                    Label("Konvertieren", systemImage: "waveform.circle.fill")
                }
                .tag(2)
        }
        .tint(.accentPurple)
    }
}

#Preview {
    ContentView()
        .environmentObject(VoiceProfileManager())
}
