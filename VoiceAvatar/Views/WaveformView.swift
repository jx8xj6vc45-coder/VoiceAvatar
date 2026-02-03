import SwiftUI

struct WaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var animationPhase: CGFloat = 0

    private let barCount = 40
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeight(for: index),
                    isActive: isActive
                )
            }
        }
        .frame(height: maxBarHeight)
        .onAppear {
            withAnimation(
                .linear(duration: 2)
                .repeatForever(autoreverses: false)
            ) {
                animationPhase = .pi * 2
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else {
            return minBarHeight
        }

        let normalizedIndex = CGFloat(index) / CGFloat(barCount)
        let wave1 = sin(normalizedIndex * .pi * 3 + animationPhase) * 0.3
        let wave2 = sin(normalizedIndex * .pi * 5 + animationPhase * 1.5) * 0.2
        let wave3 = sin(normalizedIndex * .pi * 7 + animationPhase * 0.7) * 0.1

        let combinedWave = (wave1 + wave2 + wave3 + 1) / 2
        let levelInfluence = CGFloat(audioLevel)

        let height = minBarHeight + (maxBarHeight - minBarHeight) * combinedWave * max(0.3, levelInfluence)

        return max(minBarHeight, min(maxBarHeight, height))
    }
}

struct WaveformBar: View {
    let height: CGFloat
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? Color.waveformActive : Color.waveformInactive)
            .frame(width: 4, height: height)
            .animation(.easeInOut(duration: 0.1), value: height)
    }
}

struct CircularWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        Color.accentPurple.opacity(opacity - Double(index) * 0.15),
                        lineWidth: 2
                    )
                    .scaleEffect(scale + CGFloat(index) * 0.15)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.accentPurpleLight, .accentPurple],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 80, height: 80)
                .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.3 : 1.0)

            Image(systemName: "mic.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
        }
        .frame(width: 150, height: 150)
        .onChange(of: isActive) { _, newValue in
            withAnimation(
                newValue ?
                    .easeInOut(duration: 1).repeatForever(autoreverses: true) :
                    .easeOut(duration: 0.3)
            ) {
                scale = newValue ? 1.2 : 1.0
                opacity = newValue ? 0.8 : 0.5
            }
        }
    }
}

struct AudioLevelMeter: View {
    let level: Float
    let barCount: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                let isLit = level >= threshold

                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index, isLit: isLit))
                    .frame(width: 8, height: 20)
            }
        }
    }

    private func barColor(for index: Int, isLit: Bool) -> Color {
        guard isLit else { return Color.gray.opacity(0.2) }

        let position = Float(index) / Float(barCount)
        if position < 0.6 {
            return .successGreen
        } else if position < 0.8 {
            return .warningOrange
        } else {
            return .errorRed
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        WaveformView(audioLevel: 0.5, isActive: true)

        CircularWaveformView(audioLevel: 0.6, isActive: true)

        AudioLevelMeter(level: 0.7, barCount: 20)
    }
    .padding()
}
