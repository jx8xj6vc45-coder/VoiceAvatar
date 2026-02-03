import AVFoundation
import Combine

enum RecordingState {
    case idle
    case recording
    case paused
    case playing
}

@MainActor
class AudioRecordingService: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var recordingURL: URL?
    @Published var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var levelTimer: Timer?

    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
        }
    }

    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording(filename: String? = nil) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = filename ?? "recording_\(Date().timeIntervalSince1970).m4a"
        let audioURL = documentsPath.appendingPathComponent(audioFilename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()

            recordingURL = audioURL
            recordingState = .recording
            currentTime = 0

            startTimers()
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        stopTimers()
        recordingState = .idle
        audioLevel = 0
    }

    func pauseRecording() {
        audioRecorder?.pause()
        stopTimers()
        recordingState = .paused
    }

    func resumeRecording() {
        audioRecorder?.record()
        startTimers()
        recordingState = .recording
    }

    func playRecording() {
        guard let url = recordingURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            recordingState = .playing

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.currentTime = self?.audioPlayer?.currentTime ?? 0
                }
            }
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        timer?.invalidate()
        timer = nil
        recordingState = .idle
        currentTime = 0
    }

    func deleteRecording() {
        guard let url = recordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        currentTime = 0
    }

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = self?.audioRecorder?.currentTime ?? 0
            }
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.audioRecorder?.updateMeters()
            let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
            let normalizedLevel = max(0, (level + 60) / 60)
            Task { @MainActor in
                self?.audioLevel = normalizedLevel
            }
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    func getRecordingDuration() -> TimeInterval? {
        guard let url = recordingURL else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return nil
        }
    }
}

extension AudioRecordingService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.recordingState = .idle
            self.timer?.invalidate()
            self.timer = nil
            self.currentTime = 0
        }
    }
}
