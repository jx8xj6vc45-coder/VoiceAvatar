import AVFoundation
import Accelerate

enum ConversionQuality: String, CaseIterable {
    case fast = "Schnell"
    case balanced = "Ausgewogen"
    case highQuality = "Hohe Qualität"

    var frameSize: Int {
        switch self {
        case .fast: return 1024
        case .balanced: return 2048
        case .highQuality: return 4096
        }
    }

    var hopSize: Int {
        frameSize / 4
    }
}

@MainActor
class VoiceConversionEngine: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var outputURL: URL?

    private let fileManager = FileManager.default

    func convertVoice(
        inputURL: URL,
        targetProfile: VoiceProfile,
        quality: ConversionQuality = .balanced
    ) async throws -> URL {
        isProcessing = true
        progress = 0

        defer {
            Task { @MainActor in
                self.isProcessing = false
            }
        }

        let inputCharacteristics = try await AudioAnalyzer.shared.analyzeAudioFile(at: inputURL)
        progress = 0.2

        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let frameCount = UInt32(inputFile.length)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ConversionError.bufferCreationFailed
        }
        try inputFile.read(into: inputBuffer)

        guard let inputSamples = inputBuffer.floatChannelData?[0] else {
            throw ConversionError.noAudioData
        }

        progress = 0.3

        let samples = Array(UnsafeBufferPointer(start: inputSamples, count: Int(frameCount)))
        let pitchRatio = targetProfile.characteristics.averagePitch / max(inputCharacteristics.averagePitch, 1)

        progress = 0.4

        let processedSamples = try await processAudio(
            samples: samples,
            sampleRate: Float(format.sampleRate),
            pitchRatio: pitchRatio,
            targetCharacteristics: targetProfile.characteristics,
            quality: quality
        )

        progress = 0.8

        let outputURL = try saveProcessedAudio(
            samples: processedSamples,
            format: format,
            originalURL: inputURL
        )

        progress = 1.0
        self.outputURL = outputURL

        return outputURL
    }

    private func processAudio(
        samples: [Float],
        sampleRate: Float,
        pitchRatio: Float,
        targetCharacteristics: VoiceCharacteristics,
        quality: ConversionQuality
    ) async throws -> [Float] {
        let clampedPitchRatio = max(0.5, min(2.0, pitchRatio))

        let frameSize = quality.frameSize
        let hopSize = quality.hopSize

        var outputSamples = [Float](repeating: 0, count: samples.count)
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(frameSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw ConversionError.fftSetupFailed
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var phaseAccumulator = [Float](repeating: 0, count: frameSize / 2 + 1)
        var lastPhase = [Float](repeating: 0, count: frameSize / 2 + 1)

        let numFrames = (samples.count - frameSize) / hopSize

        for frameIndex in 0..<numFrames {
            let startIndex = frameIndex * hopSize

            var frame = [Float](repeating: 0, count: frameSize)
            for i in 0..<frameSize {
                if startIndex + i < samples.count {
                    frame[i] = samples[startIndex + i] * window[i]
                }
            }

            var realPart = [Float](repeating: 0, count: frameSize / 2)
            var imagPart = [Float](repeating: 0, count: frameSize / 2)

            frame.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frameSize / 2) { complexPtr in
                    var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(frameSize / 2))
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }

            var magnitudes = [Float](repeating: 0, count: frameSize / 2)
            var phases = [Float](repeating: 0, count: frameSize / 2)

            for i in 0..<frameSize / 2 {
                magnitudes[i] = sqrt(realPart[i] * realPart[i] + imagPart[i] * imagPart[i])
                phases[i] = atan2(imagPart[i], realPart[i])
            }

            for i in 0..<frameSize / 2 {
                let phaseDiff = phases[i] - lastPhase[i]
                let expectedPhaseDiff = Float(i) * 2.0 * .pi * Float(hopSize) / Float(frameSize)
                var deltaPhase = phaseDiff - expectedPhaseDiff

                while deltaPhase > .pi { deltaPhase -= 2.0 * .pi }
                while deltaPhase < -.pi { deltaPhase += 2.0 * .pi }

                let trueFreq = Float(i) + deltaPhase * Float(frameSize) / (2.0 * .pi * Float(hopSize))
                let newBin = Int(trueFreq * clampedPitchRatio)

                if newBin >= 0 && newBin < frameSize / 2 {
                    phaseAccumulator[newBin] += 2.0 * .pi * Float(newBin) * Float(hopSize) / Float(frameSize)
                }

                lastPhase[i] = phases[i]
            }

            var newRealPart = [Float](repeating: 0, count: frameSize / 2)
            var newImagPart = [Float](repeating: 0, count: frameSize / 2)

            for i in 0..<frameSize / 2 {
                let newBin = Int(Float(i) * clampedPitchRatio)
                if newBin < frameSize / 2 {
                    newRealPart[newBin] = magnitudes[i] * cos(phaseAccumulator[newBin])
                    newImagPart[newBin] = magnitudes[i] * sin(phaseAccumulator[newBin])
                }
            }

            var outputFrame = [Float](repeating: 0, count: frameSize)

            newRealPart.withUnsafeMutableBufferPointer { realPtr in
                newImagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

                    outputFrame.withUnsafeMutableBufferPointer { outPtr in
                        outPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frameSize / 2) { complexPtr in
                            vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(frameSize / 2))
                        }
                    }
                }
            }

            var scale = 1.0 / Float(frameSize)
            vDSP_vsmul(outputFrame, 1, &scale, &outputFrame, 1, vDSP_Length(frameSize))

            for i in 0..<frameSize {
                let outIndex = startIndex + i
                if outIndex < outputSamples.count {
                    outputSamples[outIndex] += outputFrame[i] * window[i]
                }
            }

            if frameIndex % 100 == 0 {
                let currentProgress = 0.4 + 0.4 * Double(frameIndex) / Double(numFrames)
                await MainActor.run {
                    self.progress = currentProgress
                }
            }
        }

        var maxAmp: Float = 0
        vDSP_maxmgv(outputSamples, 1, &maxAmp, vDSP_Length(outputSamples.count))

        if maxAmp > 0 {
            var normalizeScale = 0.9 / maxAmp
            vDSP_vsmul(outputSamples, 1, &normalizeScale, &outputSamples, 1, vDSP_Length(outputSamples.count))
        }

        return outputSamples
    }

    private func saveProcessedAudio(samples: [Float], format: AVAudioFormat, originalURL: URL) throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputFilename = "converted_\(Date().timeIntervalSince1970).m4a"
        let outputURL = documentsPath.appendingPathComponent(outputFilename)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw ConversionError.bufferCreationFailed
        }

        outputBuffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = outputBuffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = samples[i]
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        try outputFile.write(from: outputBuffer)

        return outputURL
    }

    enum ConversionError: Error, LocalizedError {
        case bufferCreationFailed
        case noAudioData
        case fftSetupFailed
        case invalidProfile
        case processingFailed

        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed: return "Audio-Buffer konnte nicht erstellt werden"
            case .noAudioData: return "Keine Audiodaten gefunden"
            case .fftSetupFailed: return "FFT-Setup fehlgeschlagen"
            case .invalidProfile: return "Ungültiges Stimmprofil"
            case .processingFailed: return "Verarbeitung fehlgeschlagen"
            }
        }
    }
}
