import AVFoundation
import Accelerate

enum ConversionQuality: String, CaseIterable {
    case fast = "Schnell"
    case balanced = "Ausgewogen"
    case highQuality = "Hohe Qualität"

    var description: String {
        switch self {
        case .fast: return "Schnelle Verarbeitung, Basis-Qualität"
        case .balanced: return "Gute Balance zwischen Geschwindigkeit und Qualität"
        case .highQuality: return "Beste Qualität, längere Verarbeitung"
        }
    }
}

enum ConversionMethod: String, CaseIterable {
    case world = "WORLD Vocoder"
    case phaseVocoder = "Phase Vocoder"

    var description: String {
        switch self {
        case .world: return "Hohe Qualität, natürlicher Klang"
        case .phaseVocoder: return "Schnell, einfache Pitch-Änderung"
        }
    }
}

@MainActor
class VoiceConversionEngine: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var errorMessage: String?
    @Published var outputURL: URL?
    @Published var conversionMethod: ConversionMethod = .world

    private let fileManager = FileManager.default
    private let worldVocoder = WORLDVocoder.shared
    private let coreMLService = CoreMLVoiceService.shared

    private var sourceEmbedding: VoiceEmbedding?
    private var targetEmbedding: VoiceEmbedding?

    func convertVoice(
        inputURL: URL,
        targetProfile: VoiceProfile,
        quality: ConversionQuality = .balanced
    ) async throws -> URL {
        isProcessing = true
        progress = 0
        progressMessage = "Lade Audio..."

        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.progressMessage = ""
            }
        }

        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let frameCount = UInt32(inputFile.length)
        let sampleRate = Float(format.sampleRate)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ConversionError.bufferCreationFailed
        }
        try inputFile.read(into: inputBuffer)

        guard let inputSamples = inputBuffer.floatChannelData?[0] else {
            throw ConversionError.noAudioData
        }

        let samples = Array(UnsafeBufferPointer(start: inputSamples, count: Int(frameCount)))
        progress = 0.1

        progressMessage = "Analysiere Eingabe-Stimme..."
        sourceEmbedding = await coreMLService.extractVoiceEmbedding(from: samples, sampleRate: sampleRate)
        progress = 0.2

        progressMessage = "Lade Zielprofil..."
        targetEmbedding = await extractTargetEmbedding(from: targetProfile, sampleRate: sampleRate)
        progress = 0.3

        guard let source = sourceEmbedding, let target = targetEmbedding else {
            throw ConversionError.invalidProfile
        }

        let processedSamples: [Float]

        switch conversionMethod {
        case .world:
            progressMessage = "WORLD Vocoder Analyse..."
            processedSamples = try await processWithWORLD(
                samples: samples,
                sampleRate: sampleRate,
                sourceEmbedding: source,
                targetEmbedding: target,
                quality: quality
            )
        case .phaseVocoder:
            progressMessage = "Phase Vocoder Verarbeitung..."
            processedSamples = try await processWithPhaseVocoder(
                samples: samples,
                sampleRate: sampleRate,
                sourceEmbedding: source,
                targetEmbedding: target,
                quality: quality
            )
        }

        progress = 0.9
        progressMessage = "Speichere Ergebnis..."

        let outputURL = try saveProcessedAudio(
            samples: processedSamples,
            format: format,
            originalURL: inputURL
        )

        progress = 1.0
        self.outputURL = outputURL

        return outputURL
    }

    private func extractTargetEmbedding(from profile: VoiceProfile, sampleRate: Float) async -> VoiceEmbedding? {
        guard !profile.sampleURLs.isEmpty else { return nil }

        var allEmbeddings: [VoiceEmbedding] = []

        for sampleURL in profile.sampleURLs {
            do {
                let file = try AVAudioFile(forReading: sampleURL)
                let frameCount = UInt32(file.length)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                    continue
                }
                try file.read(into: buffer)

                guard let samples = buffer.floatChannelData?[0] else { continue }
                let sampleArray = Array(UnsafeBufferPointer(start: samples, count: Int(frameCount)))

                let embedding = await coreMLService.extractVoiceEmbedding(
                    from: sampleArray,
                    sampleRate: Float(file.processingFormat.sampleRate)
                )
                allEmbeddings.append(embedding)
            } catch {
                continue
            }
        }

        guard !allEmbeddings.isEmpty else { return nil }

        return averageEmbeddings(allEmbeddings)
    }

    private func averageEmbeddings(_ embeddings: [VoiceEmbedding]) -> VoiceEmbedding {
        let count = Float(embeddings.count)

        let avgF0Mean = embeddings.map(\.f0Mean).reduce(0, +) / count
        let avgF0Std = embeddings.map(\.f0Std).reduce(0, +) / count
        let avgEnergy = embeddings.map(\.energy).reduce(0, +) / count

        var avgSpectrum = [Float](repeating: 0, count: embeddings.first?.spectralEnvelope.count ?? 128)
        for emb in embeddings {
            for i in 0..<min(avgSpectrum.count, emb.spectralEnvelope.count) {
                avgSpectrum[i] += emb.spectralEnvelope[i]
            }
        }
        for i in 0..<avgSpectrum.count {
            avgSpectrum[i] /= count
        }

        var avgMFCC = [Float](repeating: 0, count: embeddings.first?.mfcc.count ?? 13)
        for emb in embeddings {
            for i in 0..<min(avgMFCC.count, emb.mfcc.count) {
                avgMFCC[i] += emb.mfcc[i]
            }
        }
        for i in 0..<avgMFCC.count {
            avgMFCC[i] /= count
        }

        let avgFormants = embeddings.first?.formants ?? [500, 1500, 2500, 3500]

        return VoiceEmbedding(
            f0Mean: avgF0Mean,
            f0Std: avgF0Std,
            spectralEnvelope: avgSpectrum,
            mfcc: avgMFCC,
            formants: avgFormants,
            energy: avgEnergy
        )
    }

    private func processWithWORLD(
        samples: [Float],
        sampleRate: Float,
        sourceEmbedding: VoiceEmbedding,
        targetEmbedding: VoiceEmbedding,
        quality: ConversionQuality
    ) async throws -> [Float] {
        progressMessage = "Extrahiere Stimmparameter..."
        let sourceParams = worldVocoder.analyze(samples: samples, sampleRate: sampleRate)
        progress = 0.5

        progressMessage = "Konvertiere Stimme..."
        let convertedParams = worldVocoder.convertVoice(
            source: sourceParams,
            targetEmbedding: targetEmbedding,
            sourceEmbedding: sourceEmbedding
        )
        progress = 0.7

        progressMessage = "Synthetisiere Audio..."
        let output = worldVocoder.synthesize(parameters: convertedParams)
        progress = 0.85

        return output
    }

    private func processWithPhaseVocoder(
        samples: [Float],
        sampleRate: Float,
        sourceEmbedding: VoiceEmbedding,
        targetEmbedding: VoiceEmbedding,
        quality: ConversionQuality
    ) async throws -> [Float] {
        let pitchRatio = sourceEmbedding.pitchRatio(to: targetEmbedding)
        let clampedPitchRatio = max(0.5, min(2.0, pitchRatio))

        let frameSize: Int
        switch quality {
        case .fast: frameSize = 1024
        case .balanced: frameSize = 2048
        case .highQuality: frameSize = 4096
        }

        let hopSize = frameSize / 4

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

        try? SecurityManager.shared.secureFile(at: outputURL)

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
