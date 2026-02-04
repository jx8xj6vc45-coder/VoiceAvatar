import Foundation
import Accelerate

class WORLDVocoder {
    static let shared = WORLDVocoder()

    private let frameShiftMs: Float = 5.0
    private let f0Floor: Float = 71.0
    private let f0Ceil: Float = 800.0

    private init() {}

    struct VoiceParameters {
        var f0: [Float]
        var spectralEnvelope: [[Float]]
        var aperiodicity: [[Float]]
        var sampleRate: Float
        var frameShift: Int

        var frameCount: Int {
            return f0.count
        }
    }

    func analyze(samples: [Float], sampleRate: Float) -> VoiceParameters {
        let frameShift = Int(sampleRate * frameShiftMs / 1000.0)
        let frameCount = (samples.count - 1) / frameShift + 1

        let f0 = extractF0DIO(samples: samples, sampleRate: sampleRate, frameShift: frameShift)
        let spectralEnvelope = extractSpectralEnvelope(samples: samples, sampleRate: sampleRate, f0: f0, frameShift: frameShift)
        let aperiodicity = estimateAperiodicity(samples: samples, sampleRate: sampleRate, f0: f0, frameShift: frameShift)

        return VoiceParameters(
            f0: f0,
            spectralEnvelope: spectralEnvelope,
            aperiodicity: aperiodicity,
            sampleRate: sampleRate,
            frameShift: frameShift
        )
    }

    func synthesize(parameters: VoiceParameters) -> [Float] {
        let outputLength = parameters.frameCount * parameters.frameShift
        var output = [Float](repeating: 0, count: outputLength)

        let fftSize = 2048

        for frame in 0..<parameters.frameCount {
            let f0 = parameters.f0[frame]
            let spectrum = parameters.spectralEnvelope[frame]
            let aperiodicity = parameters.aperiodicity[frame]

            let frameOutput = synthesizeFrame(
                f0: f0,
                spectrum: spectrum,
                aperiodicity: aperiodicity,
                sampleRate: parameters.sampleRate,
                fftSize: fftSize
            )

            let startIdx = frame * parameters.frameShift
            for i in 0..<min(frameOutput.count, outputLength - startIdx) {
                output[startIdx + i] += frameOutput[i]
            }
        }

        normalizeOutput(&output)

        return output
    }

    func convertVoice(
        source: VoiceParameters,
        targetEmbedding: VoiceEmbedding,
        sourceEmbedding: VoiceEmbedding
    ) -> VoiceParameters {
        var converted = source

        let pitchRatio = sourceEmbedding.pitchRatio(to: targetEmbedding)
        let clampedRatio = max(0.5, min(2.0, pitchRatio))

        converted.f0 = source.f0.map { f0 in
            if f0 > 0 {
                return f0 * clampedRatio
            }
            return f0
        }

        converted.spectralEnvelope = source.spectralEnvelope.map { spectrum in
            warpSpectrum(spectrum: spectrum, ratio: clampedRatio, sampleRate: source.sampleRate)
        }

        if !targetEmbedding.spectralEnvelope.isEmpty && !sourceEmbedding.spectralEnvelope.isEmpty {
            converted.spectralEnvelope = converted.spectralEnvelope.map { spectrum in
                applySpectralMapping(
                    spectrum: spectrum,
                    sourceEnvelope: sourceEmbedding.spectralEnvelope,
                    targetEnvelope: targetEmbedding.spectralEnvelope
                )
            }
        }

        return converted
    }

    private func extractF0DIO(samples: [Float], sampleRate: Float, frameShift: Int) -> [Float] {
        let frameCount = (samples.count - 1) / frameShift + 1
        var f0 = [Float](repeating: 0, count: frameCount)

        let windowSize = Int(sampleRate / f0Floor * 4)

        for frame in 0..<frameCount {
            let center = frame * frameShift
            let start = max(0, center - windowSize / 2)
            let end = min(samples.count, center + windowSize / 2)

            guard end - start > 100 else { continue }

            let frameSamples = Array(samples[start..<end])

            if let estimatedF0 = estimateF0ForFrame(samples: frameSamples, sampleRate: sampleRate) {
                f0[frame] = estimatedF0
            }
        }

        f0 = smoothF0(f0)

        return f0
    }

    private func estimateF0ForFrame(samples: [Float], sampleRate: Float) -> Float? {
        let n = samples.count
        let tauMax = Int(sampleRate / f0Floor)
        let tauMin = Int(sampleRate / f0Ceil)

        guard tauMax < n / 2, tauMin < tauMax else { return nil }

        var acf = [Float](repeating: 0, count: tauMax + 1)

        for tau in 0...tauMax {
            var sum: Float = 0
            var count = 0
            for i in 0..<(n - tau) {
                sum += samples[i] * samples[i + tau]
                count += 1
            }
            acf[tau] = count > 0 ? sum / Float(count) : 0
        }

        guard acf[0] > 0 else { return nil }

        for i in 0...tauMax {
            acf[i] /= acf[0]
        }

        var bestTau = tauMin
        var bestScore: Float = -1

        for tau in tauMin...tauMax {
            if tau > 0 && tau < tauMax {
                if acf[tau] > acf[tau - 1] && acf[tau] > acf[tau + 1] {
                    if acf[tau] > bestScore {
                        bestScore = acf[tau]
                        bestTau = tau
                    }
                }
            }
        }

        if bestScore > 0.3 {
            return sampleRate / Float(bestTau)
        }

        return nil
    }

    private func smoothF0(_ f0: [Float]) -> [Float] {
        var smoothed = f0
        let windowSize = 5

        for i in 0..<f0.count {
            var sum: Float = 0
            var count = 0

            for j in max(0, i - windowSize / 2)...min(f0.count - 1, i + windowSize / 2) {
                if f0[j] > 0 {
                    sum += f0[j]
                    count += 1
                }
            }

            if count > 0 && f0[i] > 0 {
                smoothed[i] = sum / Float(count)
            }
        }

        return smoothed
    }

    private func extractSpectralEnvelope(samples: [Float], sampleRate: Float, f0: [Float], frameShift: Int) -> [[Float]] {
        let fftSize = 2048
        let spectrumSize = fftSize / 2 + 1
        var envelopes = [[Float]]()

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        for frame in 0..<f0.count {
            let center = frame * frameShift
            let start = max(0, center - fftSize / 2)
            let end = min(samples.count, start + fftSize)

            var frameSamples = [Float](repeating: 0, count: fftSize)
            for i in start..<end {
                frameSamples[i - start] = samples[i]
            }

            vDSP_vmul(frameSamples, 1, window, 1, &frameSamples, 1, vDSP_Length(fftSize))

            let spectrum = computeSpectrum(samples: frameSamples, fftSize: fftSize)

            var envelope = [Float](repeating: 0, count: spectrumSize)
            let smoothingOrder = 20

            for i in 0..<spectrumSize {
                var sum: Float = 0
                var count = 0
                for j in max(0, i - smoothingOrder)...min(spectrumSize - 1, i + smoothingOrder) {
                    sum += spectrum[j]
                    count += 1
                }
                envelope[i] = sum / Float(count)
            }

            envelopes.append(envelope)
        }

        return envelopes
    }

    private func computeSpectrum(samples: [Float], fftSize: Int) -> [Float] {
        let log2n = vDSP_Length(log2(Float(fftSize)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: fftSize / 2 + 1)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)

        samples.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        var magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
        for i in 0..<fftSize / 2 {
            magnitudes[i] = sqrt(real[i] * real[i] + imag[i] * imag[i])
        }

        return magnitudes
    }

    private func estimateAperiodicity(samples: [Float], sampleRate: Float, f0: [Float], frameShift: Int) -> [[Float]] {
        let spectrumSize = 1025
        var aperiodicity = [[Float]]()

        for frame in 0..<f0.count {
            var ap = [Float](repeating: 0.5, count: spectrumSize)

            if f0[frame] == 0 {
                ap = [Float](repeating: 1.0, count: spectrumSize)
            } else {
                for i in 0..<spectrumSize {
                    let freq = Float(i) * sampleRate / Float((spectrumSize - 1) * 2)
                    if freq < f0[frame] * 0.5 || freq > sampleRate / 2 * 0.9 {
                        ap[i] = 0.9
                    } else {
                        ap[i] = 0.1
                    }
                }
            }

            aperiodicity.append(ap)
        }

        return aperiodicity
    }

    private func synthesizeFrame(
        f0: Float,
        spectrum: [Float],
        aperiodicity: [Float],
        sampleRate: Float,
        fftSize: Int
    ) -> [Float] {
        let frameLength = Int(sampleRate * frameShiftMs / 1000.0) * 2

        var output = [Float](repeating: 0, count: frameLength)

        if f0 > 0 {
            let period = sampleRate / f0
            var phase: Float = 0

            for i in 0..<frameLength {
                let periodicComponent = sin(phase)

                let noiseComponent = Float.random(in: -1...1)

                let freqBin = Int(f0 / sampleRate * Float(spectrum.count))
                let ap = freqBin < aperiodicity.count ? aperiodicity[freqBin] : 0.5

                output[i] = (1 - ap) * periodicComponent + ap * noiseComponent

                phase += 2 * .pi / period
                if phase > 2 * .pi {
                    phase -= 2 * .pi
                }
            }
        } else {
            for i in 0..<frameLength {
                output[i] = Float.random(in: -0.1...0.1)
            }
        }

        var window = [Float](repeating: 0, count: frameLength)
        vDSP_hann_window(&window, vDSP_Length(frameLength), Int32(vDSP_HANN_NORM))
        vDSP_vmul(output, 1, window, 1, &output, 1, vDSP_Length(frameLength))

        return output
    }

    private func warpSpectrum(spectrum: [Float], ratio: Float, sampleRate: Float) -> [Float] {
        var warped = [Float](repeating: 0, count: spectrum.count)

        for i in 0..<spectrum.count {
            let originalIdx = Float(i) / ratio
            let idx0 = Int(originalIdx)
            let idx1 = min(idx0 + 1, spectrum.count - 1)
            let frac = originalIdx - Float(idx0)

            if idx0 >= 0 && idx0 < spectrum.count {
                warped[i] = spectrum[idx0] * (1 - frac) + spectrum[idx1] * frac
            }
        }

        return warped
    }

    private func applySpectralMapping(
        spectrum: [Float],
        sourceEnvelope: [Float],
        targetEnvelope: [Float]
    ) -> [Float] {
        var mapped = spectrum

        let minLength = min(spectrum.count, min(sourceEnvelope.count, targetEnvelope.count))

        for i in 0..<minLength {
            if sourceEnvelope[i] > 0.001 {
                let ratio = targetEnvelope[i] / sourceEnvelope[i]
                let clampedRatio = max(0.1, min(10.0, ratio))
                mapped[i] = spectrum[i] * clampedRatio
            }
        }

        return mapped
    }

    private func normalizeOutput(_ samples: inout [Float]) {
        var maxAmp: Float = 0
        vDSP_maxmgv(samples, 1, &maxAmp, vDSP_Length(samples.count))

        if maxAmp > 0 {
            var scale = 0.9 / maxAmp
            vDSP_vsmul(samples, 1, &scale, &samples, 1, vDSP_Length(samples.count))
        }
    }
}
