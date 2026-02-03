import SwiftUI
import AVFoundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var selectedProfile: VoiceProfile?
    @Published var isPlayingSample = false
    @Published var currentSampleIndex: Int?
    @Published var showDeleteConfirmation = false
    @Published var profileToDelete: VoiceProfile?

    private var audioPlayer: AVAudioPlayer?

    func playSample(at index: Int, from profile: VoiceProfile) {
        guard index < profile.sampleURLs.count else { return }

        stopPlayback()

        let url = profile.sampleURLs[index]
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlayingSample = true
            currentSampleIndex = index
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingSample = false
        currentSampleIndex = nil
    }

    func confirmDelete(_ profile: VoiceProfile) {
        profileToDelete = profile
        showDeleteConfirmation = true
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }

    func formatCharacteristic(_ value: Float, unit: String = "") -> String {
        return String(format: "%.1f%@", value, unit)
    }
}

extension ProfileViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingSample = false
            self.currentSampleIndex = nil
        }
    }
}
