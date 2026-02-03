import SwiftUI
import AVFoundation

@MainActor
class ConversionViewModel: ObservableObject {
    @Published var recordingService = AudioRecordingService()
    @Published var conversionEngine = VoiceConversionEngine()

    @Published var selectedQuality: ConversionQuality = .balanced
    @Published var inputRecordingURL: URL?
    @Published var convertedAudioURL: URL?

    @Published var isConverting = false
    @Published var conversionProgress: Double = 0

    @Published var showError = false
    @Published var errorMessage = ""

    @Published var isPlayingOriginal = false
    @Published var isPlayingConverted = false

    private var audioPlayer: AVAudioPlayer?

    var hasInputRecording: Bool {
        inputRecordingURL != nil
    }

    var hasConvertedAudio: Bool {
        convertedAudioURL != nil
    }

    func startRecording() {
        Task {
            let granted = await recordingService.requestPermission()
            if granted {
                convertedAudioURL = nil
                recordingService.startRecording()
            } else {
                errorMessage = "Mikrofonzugriff wurde verweigert."
                showError = true
            }
        }
    }

    func stopRecording() {
        recordingService.stopRecording()
        inputRecordingURL = recordingService.recordingURL
    }

    func convert(with profile: VoiceProfile) async {
        guard let inputURL = inputRecordingURL else {
            errorMessage = "Keine Aufnahme vorhanden"
            showError = true
            return
        }

        guard profile.hasEnoughSamples else {
            errorMessage = "Das Profil benötigt mindestens 3 Samples"
            showError = true
            return
        }

        isConverting = true
        conversionProgress = 0

        do {
            let outputURL = try await conversionEngine.convertVoice(
                inputURL: inputURL,
                targetProfile: profile,
                quality: selectedQuality
            )

            convertedAudioURL = outputURL
            isConverting = false
            conversionProgress = 1.0
        } catch {
            isConverting = false
            errorMessage = "Konvertierung fehlgeschlagen: \(error.localizedDescription)"
            showError = true
        }
    }

    func playOriginal() {
        guard let url = inputRecordingURL else { return }
        stopAllPlayback()
        play(url: url)
        isPlayingOriginal = true
    }

    func playConverted() {
        guard let url = convertedAudioURL else { return }
        stopAllPlayback()
        play(url: url)
        isPlayingConverted = true
    }

    func stopAllPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingOriginal = false
        isPlayingConverted = false
    }

    private func play(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            errorMessage = "Wiedergabe fehlgeschlagen: \(error.localizedDescription)"
            showError = true
        }
    }

    func reset() {
        stopAllPlayback()

        if let url = inputRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = convertedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }

        inputRecordingURL = nil
        convertedAudioURL = nil
        conversionProgress = 0
    }

    func shareConvertedAudio() -> URL? {
        return convertedAudioURL
    }
}

extension ConversionViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingOriginal = false
            self.isPlayingConverted = false
        }
    }
}
