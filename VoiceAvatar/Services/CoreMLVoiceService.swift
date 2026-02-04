import Foundation
import CoreML
import Accelerate

enum VoiceModelType: String, CaseIterable {
    case embedded = "Eingebettet (Basis)"
    case custom = "Benutzerdefiniert"

    var description: String {
        switch self {
        case .embedded: return "Grundlegende Voice Conversion ohne ML"
        case .custom: return "Eigenes trainiertes Modell"
        }
    }
}

@MainActor
class CoreMLVoiceService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var modelType: VoiceModelType = .embedded
    @Published var loadingProgress: Double = 0
    @Published var errorMessage: String?

    private var voiceEncoder: MLModel?
    private var voiceDecoder: MLModel?
    private var voiceConverter: MLModel?

    static let shared = CoreMLVoiceService()

    private init() {
        Task {
            await loadModels()
        }
    }

    func loadModels() async {
        loadingProgress = 0.1

        if let encoderURL = Bundle.main.url(forResource: "VoiceEncoder", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                voiceEncoder = try MLModel(contentsOf: encoderURL, configuration: config)
                loadingProgress = 0.4
            } catch {
                print("Voice Encoder nicht gefunden - verwende DSP Fallback")
            }
        }

        if let converterURL = Bundle.main.url(forResource: "VoiceConverter", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                voiceConverter = try MLModel(contentsOf: converterURL, configuration: config)
                loadingProgress = 0.7
            } catch {
                print("Voice Converter nicht gefunden - verwende DSP Fallback")
            }
        }

        if let decoderURL = Bundle.main.url(forResource: "VoiceDecoder", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                voiceDecoder = try MLModel(contentsOf: decoderURL, configuration: config)
                loadingProgress = 1.0
            } catch {
                print("Voice Decoder nicht gefunden - verwende DSP Fallback")
            }
        }

        isModelLoaded = voiceEncoder != nil && voiceConverter != nil && voiceDecoder != nil
        modelType = isModelLoaded ? .custom : .embedded

        loadingProgress = 1.0
    }

    func loadCustomModel(from url: URL) async throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let compiledURL = try MLModel.compileModel(at: url)
        voiceConverter = try MLModel(contentsOf: compiledURL, configuration: config)

        isModelLoaded = true
        modelType = .custom
    }

    func extractVoiceEmbedding(from audioSamples: [Float], sampleRate: Float) async -> VoiceEmbedding {
        if let encoder = voiceEncoder {
            return await extractWithML(samples: audioSamples, sampleRate: sampleRate, encoder: encoder)
        } else {
            return extractWithDSP(samples: audioSamples, sampleRate: sampleRate)
        }
    }

    private func extractWithML(samples: [Float], sampleRate: Float, encoder: MLModel) async -> VoiceEmbedding {
        return extractWithDSP(samples: samples, sampleRate: sampleRate)
    }

    private func extractWithDSP(samples: [Float], sampleRate: Float) -> VoiceEmbedding {
        let f0 = extractF0(samples: samples, sampleRate: sampleRate)
        let spectralEnvelope = extractSpectralEnvelope(samples: samples, sampleRate: sampleRate)
        let mfcc = extractMFCC(samples: samples, sampleRate: sampleRate)
        let formants = extractFormants(samples: samples, sampleRate: sampleRate)

        return VoiceEmbedding(
            f0Mean: f0.mean,
            f0Std: f0.std,
            spectralEnvelope: spectralEnvelope,
            mfcc: mfcc,
            formants: formants,
            energy: calculateRMSEnergy(samples: samples)
        )
    }

    private func extractF0(samples: [Float], sampleRate: Float) -> (mean: Float, std: Float) {
        let frameSize = 2048
        let hopSize = 512
        var f0Values: [Float] = []

        for i in stride(from: 0, to: samples.count - frameSize, by: hopSize) {
            let frame = Array(samples[i..<(i + frameSize)])
            if let f0 = estimateF0WithYIN(frame: frame, sampleRate: sampleRate) {
                if f0 > 50 && f0 < 600 {
                    f0Values.append(f0)
                }
            }
        }

        guard !f0Values.isEmpty else {
            return (mean: 150, std: 30)
        }

        let mean = f0Values.reduce(0, +) / Float(f0Values.count)
        let variance = f0Values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(f0Values.count)

        return (mean: mean, std: sqrt(variance))
    }

    private func estimateF0WithYIN(frame: [Float], sampleRate: Float) -> Float? {
        let frameSize = frame.count
        let tauMax = Int(sampleRate / 50)
        let tauMin = Int(sampleRate / 600)

        guard tauMax < frameSize / 2 else { return nil }

        var d = [Float](repeating: 0, count: tauMax)

        for tau in 1..<tauMax {
            var sum: Float = 0
            for j in 0..<(frameSize - tauMax) {
                let diff = frame[j] - frame[j + tau]
                sum += diff * diff
            }
            d[tau] = sum
        }

        var cumulativeSum: Float = 0
        var dPrime = [Float](repeating: 1, count: tauMax)

        for tau in 1..<tauMax {
            cumulativeSum += d[tau]
            if cumulativeSum > 0 {
                dPrime[tau] = d[tau] * Float(tau) / cumulativeSum
            }
        }

        let threshold: Float = 0.1
        for tau in tauMin..<tauMax {
            if dPrime[tau] < threshold {
                var minTau = tau
                for t in tau..<min(tau + 4, tauMax) {
                    if dPrime[t] < dPrime[minTau] {
                        minTau = t
                    }
                }
                return sampleRate / Float(minTau)
            }
        }

        return nil
    }

    private func extractSpectralEnvelope(samples: [Float], sampleRate: Float) -> [Float] {
        let fftSize = 2048
        let numBins = 128

        guard samples.count >= fftSize else {
            return [Float](repeating: 0, count: numBins)
        }

        var envelope = [Float](repeating: 0, count: numBins)
        var frameCount = 0

        for i in stride(from: 0, to: samples.count - fftSize, by: fftSize / 2) {
            let frame = Array(samples[i..<(i + fftSize)])
            let spectrum = computeFFTMagnitude(frame: frame)

            let binSize = spectrum.count / numBins
            for bin in 0..<numBins {
                let start = bin * binSize
                let end = min(start + binSize, spectrum.count)
                let binMagnitude = spectrum[start..<end].max() ?? 0
                envelope[bin] += binMagnitude
            }
            frameCount += 1
        }

        if frameCount > 0 {
            for i in 0..<numBins {
                envelope[i] /= Float(frameCount)
            }
        }

        return envelope
    }

    private func computeFFTMagnitude(frame: [Float]) -> [Float] {
        let n = frame.count
        let log2n = vDSP_Length(log2(Float(n)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: n / 2)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)

        frame.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n / 2))
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        var magnitudes = [Float](repeating: 0, count: n / 2)
        for i in 0..<n / 2 {
            magnitudes[i] = sqrt(real[i] * real[i] + imag[i] * imag[i])
        }

        return magnitudes
    }

    private func extractMFCC(samples: [Float], sampleRate: Float) -> [Float] {
        let numCoeffs = 13
        let fftSize = 2048
        let numFilters = 26

        guard samples.count >= fftSize else {
            return [Float](repeating: 0, count: numCoeffs)
        }

        let spectrum = computeFFTMagnitude(frame: Array(samples.prefix(fftSize)))

        var melFilterBank = [[Float]](repeating: [Float](repeating: 0, count: spectrum.count), count: numFilters)
        let melMin = hzToMel(0)
        let melMax = hzToMel(sampleRate / 2)
        let melStep = (melMax - melMin) / Float(numFilters + 1)

        for i in 0..<numFilters {
            let melStart = melMin + Float(i) * melStep
            let melCenter = melMin + Float(i + 1) * melStep
            let melEnd = melMin + Float(i + 2) * melStep

            let hzStart = melToHz(melStart)
            let hzCenter = melToHz(melCenter)
            let hzEnd = melToHz(melEnd)

            for j in 0..<spectrum.count {
                let hz = Float(j) * sampleRate / Float(fftSize)
                if hz >= hzStart && hz <= hzCenter {
                    melFilterBank[i][j] = (hz - hzStart) / (hzCenter - hzStart)
                } else if hz > hzCenter && hz <= hzEnd {
                    melFilterBank[i][j] = (hzEnd - hz) / (hzEnd - hzCenter)
                }
            }
        }

        var melEnergies = [Float](repeating: 0, count: numFilters)
        for i in 0..<numFilters {
            for j in 0..<spectrum.count {
                melEnergies[i] += spectrum[j] * melFilterBank[i][j]
            }
            melEnergies[i] = log(max(melEnergies[i], 1e-10))
        }

        var mfcc = [Float](repeating: 0, count: numCoeffs)
        for i in 0..<numCoeffs {
            for j in 0..<numFilters {
                mfcc[i] += melEnergies[j] * cos(Float.pi * Float(i) * (Float(j) + 0.5) / Float(numFilters))
            }
        }

        return mfcc
    }

    private func hzToMel(_ hz: Float) -> Float {
        return 2595 * log10(1 + hz / 700)
    }

    private func melToHz(_ mel: Float) -> Float {
        return 700 * (pow(10, mel / 2595) - 1)
    }

    private func extractFormants(samples: [Float], sampleRate: Float) -> [Float] {
        return [500, 1500, 2500, 3500]
    }

    private func calculateRMSEnergy(samples: [Float]) -> Float {
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return sqrt(sumSquares / Float(samples.count))
    }
}

struct VoiceEmbedding: Codable, Equatable {
    var f0Mean: Float
    var f0Std: Float
    var spectralEnvelope: [Float]
    var mfcc: [Float]
    var formants: [Float]
    var energy: Float

    static let empty = VoiceEmbedding(
        f0Mean: 0,
        f0Std: 0,
        spectralEnvelope: [],
        mfcc: [],
        formants: [],
        energy: 0
    )

    func pitchRatio(to target: VoiceEmbedding) -> Float {
        guard f0Mean > 0 && target.f0Mean > 0 else { return 1.0 }
        return target.f0Mean / f0Mean
    }

    func energyRatio(to target: VoiceEmbedding) -> Float {
        guard energy > 0 && target.energy > 0 else { return 1.0 }
        return target.energy / energy
    }
}
