import AVFoundation
import Accelerate

class AudioAnalyzer {
    static let shared = AudioAnalyzer()

    private init() {}

    func analyzeAudioFile(at url: URL) async throws -> VoiceCharacteristics {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AnalyzerError.bufferCreationFailed
        }

        try file.read(into: buffer)

        guard let floatData = buffer.floatChannelData?[0] else {
            throw AnalyzerError.noAudioData
        }

        let sampleRate = Float(format.sampleRate)
        let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(frameCount)))

        let pitch = estimatePitch(samples: samples, sampleRate: sampleRate)
        let energy = calculateEnergy(samples: samples)
        let spectralCentroid = calculateSpectralCentroid(samples: samples, sampleRate: sampleRate)
        let formants = estimateFormants(samples: samples, sampleRate: sampleRate)

        return VoiceCharacteristics(
            averagePitch: pitch.average,
            pitchVariance: pitch.variance,
            averageEnergy: energy,
            speakingRate: estimateSpeakingRate(samples: samples, sampleRate: sampleRate),
            spectralCentroid: spectralCentroid,
            formantFrequencies: formants
        )
    }

    func analyzeMultipleSamples(urls: [URL]) async throws -> VoiceCharacteristics {
        var allCharacteristics: [VoiceCharacteristics] = []

        for url in urls {
            let characteristics = try await analyzeAudioFile(at: url)
            allCharacteristics.append(characteristics)
        }

        return averageCharacteristics(allCharacteristics)
    }

    private func estimatePitch(samples: [Float], sampleRate: Float) -> (average: Float, variance: Float) {
        let frameSize = 2048
        let hopSize = 512
        var pitches: [Float] = []

        for i in stride(from: 0, to: samples.count - frameSize, by: hopSize) {
            let frame = Array(samples[i..<(i + frameSize)])
            if let pitch = autocorrelationPitch(frame: frame, sampleRate: sampleRate) {
                if pitch > 50 && pitch < 500 {
                    pitches.append(pitch)
                }
            }
        }

        guard !pitches.isEmpty else {
            return (average: 150, variance: 20)
        }

        let average = pitches.reduce(0, +) / Float(pitches.count)
        let variance = pitches.map { pow($0 - average, 2) }.reduce(0, +) / Float(pitches.count)

        return (average: average, variance: sqrt(variance))
    }

    private func autocorrelationPitch(frame: [Float], sampleRate: Float) -> Float? {
        let n = frame.count
        var autocorr = [Float](repeating: 0, count: n)

        vDSP_conv(frame, 1, frame.reversed(), 1, &autocorr, 1, vDSP_Length(n), vDSP_Length(n))

        let minLag = Int(sampleRate / 500)
        let maxLag = Int(sampleRate / 50)

        guard maxLag < n && minLag < maxLag else { return nil }

        var maxValue: Float = 0
        var maxIndex = minLag

        for i in minLag..<min(maxLag, n) {
            if autocorr[i] > maxValue {
                maxValue = autocorr[i]
                maxIndex = i
            }
        }

        guard maxValue > autocorr[0] * 0.1 else { return nil }

        return sampleRate / Float(maxIndex)
    }

    private func calculateEnergy(samples: [Float]) -> Float {
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return sqrt(sumSquares / Float(samples.count))
    }

    private func calculateSpectralCentroid(samples: [Float], sampleRate: Float) -> Float {
        let fftSize = 2048
        guard samples.count >= fftSize else { return 0 }

        let frame = Array(samples.prefix(fftSize))
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return 0
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)

        frame.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var weightedSum: Float = 0
        var totalMagnitude: Float = 0

        for i in 0..<magnitudes.count {
            let frequency = Float(i) * sampleRate / Float(fftSize)
            weightedSum += frequency * magnitudes[i]
            totalMagnitude += magnitudes[i]
        }

        return totalMagnitude > 0 ? weightedSum / totalMagnitude : 0
    }

    private func estimateFormants(samples: [Float], sampleRate: Float) -> [Float] {
        return [500, 1500, 2500]
    }

    private func estimateSpeakingRate(samples: [Float], sampleRate: Float) -> Float {
        let frameSize = 1024
        var energies: [Float] = []

        for i in stride(from: 0, to: samples.count - frameSize, by: frameSize) {
            let frame = Array(samples[i..<(i + frameSize)])
            var energy: Float = 0
            vDSP_svesq(frame, 1, &energy, vDSP_Length(frameSize))
            energies.append(sqrt(energy / Float(frameSize)))
        }

        let threshold = (energies.max() ?? 0) * 0.3
        var syllableCount = 0
        var wasBelowThreshold = true

        for energy in energies {
            if energy > threshold && wasBelowThreshold {
                syllableCount += 1
                wasBelowThreshold = false
            } else if energy < threshold {
                wasBelowThreshold = true
            }
        }

        let durationSeconds = Float(samples.count) / sampleRate
        return Float(syllableCount) / durationSeconds * 60
    }

    private func averageCharacteristics(_ characteristics: [VoiceCharacteristics]) -> VoiceCharacteristics {
        guard !characteristics.isEmpty else {
            return VoiceCharacteristics()
        }

        let count = Float(characteristics.count)

        return VoiceCharacteristics(
            averagePitch: characteristics.map(\.averagePitch).reduce(0, +) / count,
            pitchVariance: characteristics.map(\.pitchVariance).reduce(0, +) / count,
            averageEnergy: characteristics.map(\.averageEnergy).reduce(0, +) / count,
            speakingRate: characteristics.map(\.speakingRate).reduce(0, +) / count,
            spectralCentroid: characteristics.map(\.spectralCentroid).reduce(0, +) / count,
            formantFrequencies: characteristics.first?.formantFrequencies ?? []
        )
    }

    enum AnalyzerError: Error, LocalizedError {
        case bufferCreationFailed
        case noAudioData
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed: return "Failed to create audio buffer"
            case .noAudioData: return "No audio data found"
            case .invalidFormat: return "Invalid audio format"
            }
        }
    }
}
