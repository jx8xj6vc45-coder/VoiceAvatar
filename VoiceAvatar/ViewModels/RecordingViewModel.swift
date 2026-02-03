import SwiftUI
import Combine

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var recordingService = AudioRecordingService()
    @Published var currentStep: ProfileCreationStep = .naming
    @Published var profileName = ""
    @Published var recordedSamples: [URL] = []
    @Published var isAnalyzing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var createdProfile: VoiceProfile?

    private var profileManager: VoiceProfileManager?
    private var cancellables = Set<AnyCancellable>()

    let samplePrompts = [
        "Lies diesen Satz laut vor: 'Der schnelle braune Fuchs springt über den faulen Hund.'",
        "Zähle langsam von eins bis zehn.",
        "Beschreibe in zwei Sätzen, was du heute gemacht hast.",
        "Sage: 'Hallo, mein Name ist... und ich freue mich, hier zu sein.'",
        "Lies vor: 'Die Sonne scheint hell am blauen Himmel.'"
    ]

    var currentPrompt: String {
        let index = recordedSamples.count % samplePrompts.count
        return samplePrompts[index]
    }

    var canProceedFromNaming: Bool {
        !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canProceedFromRecording: Bool {
        recordedSamples.count >= 3
    }

    var recordingProgress: Double {
        Double(recordedSamples.count) / 3.0
    }

    func setProfileManager(_ manager: VoiceProfileManager) {
        self.profileManager = manager
    }

    func nextStep() {
        guard let next = ProfileCreationStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation {
            currentStep = next
        }

        if currentStep == .analyzing {
            Task {
                await analyzeAndCreateProfile()
            }
        }
    }

    func previousStep() {
        guard let previous = ProfileCreationStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation {
            currentStep = previous
        }
    }

    func startRecording() {
        Task {
            let granted = await recordingService.requestPermission()
            if granted {
                recordingService.startRecording()
            } else {
                errorMessage = "Mikrofonzugriff wurde verweigert. Bitte in den Einstellungen aktivieren."
                showError = true
            }
        }
    }

    func stopRecording() {
        recordingService.stopRecording()
        if let url = recordingService.recordingURL {
            recordedSamples.append(url)
        }
    }

    func playLastRecording() {
        recordingService.playRecording()
    }

    func deleteLastRecording() {
        guard !recordedSamples.isEmpty else { return }
        let lastURL = recordedSamples.removeLast()
        try? FileManager.default.removeItem(at: lastURL)
    }

    func reset() {
        currentStep = .naming
        profileName = ""
        recordedSamples.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        recordedSamples = []
        isAnalyzing = false
        createdProfile = nil
    }

    private func analyzeAndCreateProfile() async {
        guard let manager = profileManager else {
            errorMessage = "Profile Manager nicht verfügbar"
            showError = true
            return
        }

        isAnalyzing = true

        do {
            let characteristics = try await AudioAnalyzer.shared.analyzeMultipleSamples(urls: recordedSamples)

            var profile = manager.createProfile(name: profileName)

            for sampleURL in recordedSamples {
                manager.addSampleToProfile(profile.id, sampleURL: sampleURL)
            }

            if let index = manager.profiles.firstIndex(where: { $0.id == profile.id }) {
                manager.profiles[index].characteristics = characteristics
                profile = manager.profiles[index]
            }

            createdProfile = profile
            isAnalyzing = false

            withAnimation {
                currentStep = .complete
            }
        } catch {
            isAnalyzing = false
            errorMessage = "Analyse fehlgeschlagen: \(error.localizedDescription)"
            showError = true
            previousStep()
        }
    }
}
