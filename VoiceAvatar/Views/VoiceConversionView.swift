import SwiftUI

struct VoiceConversionView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @StateObject private var viewModel = ConversionViewModel()

    @State private var showProfilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    profileSelectionSection

                    recordingSection

                    if viewModel.hasInputRecording {
                        conversionSection
                    }

                    if viewModel.hasConvertedAudio {
                        resultSection
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Konvertieren")
            .sheet(isPresented: $showProfilePicker) {
                ProfilePickerView(selectedProfile: $profileManager.activeProfile)
            }
            .alert("Fehler", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.linearGradient(
                    colors: [.accentPurple, .accentPurpleLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Stimme transformieren")
                .font(.title2)
                .fontWeight(.bold)

            Text("Nimm etwas auf und konvertiere es in dein Stimmprofil")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var profileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zielprofil")
                .font(.headline)

            Button(action: { showProfilePicker = true }) {
                HStack {
                    if let profile = profileManager.activeProfile {
                        Image(systemName: "person.wave.2.fill")
                            .foregroundColor(.accentPurple)

                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.textPrimary)

                            Text("\(profile.totalSamples) Samples")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        if profile.hasEnoughSamples {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.successGreen)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.warningOrange)
                        }
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.accentPurple)

                        Text("Profil auswählen")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)

                        Spacer()
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(12)
            }

            if let profile = profileManager.activeProfile, !profile.hasEnoughSamples {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.warningOrange)
                    Text("Das Profil benötigt mindestens 3 Samples für die Konvertierung")
                        .font(.caption)
                        .foregroundColor(.warningOrange)
                }
            }
        }
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aufnahme")
                .font(.headline)

            VStack(spacing: 16) {
                CircularWaveformView(
                    audioLevel: viewModel.recordingService.audioLevel,
                    isActive: viewModel.recordingService.recordingState == .recording
                )

                if viewModel.recordingService.recordingState == .recording {
                    Text(formatTime(viewModel.recordingService.currentTime))
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundColor(.accentPurple)
                }

                HStack(spacing: 20) {
                    if viewModel.hasInputRecording {
                        Button(action: { viewModel.reset() }) {
                            Image(systemName: "trash.fill")
                                .font(.title2)
                                .foregroundColor(.errorRed)
                                .frame(width: 50, height: 50)
                                .background(Color.backgroundSecondary)
                                .cornerRadius(25)
                        }
                    }

                    Button(action: {
                        if viewModel.recordingService.recordingState == .recording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        Image(systemName: viewModel.recordingService.recordingState == .recording ?
                              "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(viewModel.recordingService.recordingState == .recording ?
                                        Color.errorRed : Color.accentPurple)
                            .cornerRadius(35)
                    }

                    if viewModel.hasInputRecording {
                        Button(action: {
                            if viewModel.isPlayingOriginal {
                                viewModel.stopAllPlayback()
                            } else {
                                viewModel.playOriginal()
                            }
                        }) {
                            Image(systemName: viewModel.isPlayingOriginal ? "stop.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.accentPurple)
                                .frame(width: 50, height: 50)
                                .background(Color.backgroundSecondary)
                                .cornerRadius(25)
                        }
                    }
                }

                if viewModel.hasInputRecording {
                    Text("Aufnahme bereit")
                        .font(.caption)
                        .foregroundColor(.successGreen)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.backgroundSecondary)
            .cornerRadius(16)
        }
    }

    private var conversionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konvertierung")
                .font(.headline)

            VStack(spacing: 16) {
                HStack {
                    Text("Qualität")
                        .font(.subheadline)

                    Spacer()

                    Picker("Qualität", selection: $viewModel.selectedQuality) {
                        ForEach(ConversionQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                if viewModel.isConverting {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.conversionProgress)
                            .tint(.accentPurple)

                        Text("\(Int(viewModel.conversionProgress * 100))% verarbeitet")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    Button(action: {
                        guard let profile = profileManager.activeProfile else { return }
                        Task {
                            await viewModel.convert(with: profile)
                        }
                    }) {
                        Label("Konvertieren", systemImage: "waveform.path.ecg")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canConvert ? Color.accentPurple : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canConvert)
                }
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(16)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ergebnis")
                    .font(.headline)

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.successGreen)
            }

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Original")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        Button(action: {
                            if viewModel.isPlayingOriginal {
                                viewModel.stopAllPlayback()
                            } else {
                                viewModel.playOriginal()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: viewModel.isPlayingOriginal ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 40))
                                Text(viewModel.isPlayingOriginal ? "Stop" : "Abspielen")
                                    .font(.caption)
                            }
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.backgroundTertiary)
                            .cornerRadius(12)
                        }
                    }

                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundColor(.accentPurple)

                    VStack(spacing: 8) {
                        Text("Konvertiert")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        Button(action: {
                            if viewModel.isPlayingConverted {
                                viewModel.stopAllPlayback()
                            } else {
                                viewModel.playConverted()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: viewModel.isPlayingConverted ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 40))
                                Text(viewModel.isPlayingConverted ? "Stop" : "Abspielen")
                                    .font(.caption)
                            }
                            .foregroundColor(.accentPurple)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentPurple.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }

                if let url = viewModel.shareConvertedAudio() {
                    ShareLink(item: url) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundColor(.accentPurple)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.backgroundTertiary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(16)
        }
    }

    private var canConvert: Bool {
        viewModel.hasInputRecording &&
        profileManager.activeProfile != nil &&
        profileManager.activeProfile?.hasEnoughSamples == true &&
        !viewModel.isConverting
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ProfilePickerView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @Binding var selectedProfile: VoiceProfile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if profileManager.profiles.isEmpty {
                    Text("Keine Profile vorhanden")
                        .foregroundColor(.textSecondary)
                } else {
                    ForEach(profileManager.profiles) { profile in
                        Button(action: {
                            selectedProfile = profile
                            profileManager.setActiveProfile(profile)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "person.wave.2.fill")
                                    .foregroundColor(.accentPurple)

                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.subheadline)
                                        .foregroundColor(.textPrimary)

                                    Text("\(profile.totalSamples) Samples")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                if selectedProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentPurple)
                                }

                                if !profile.hasEnoughSamples {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.warningOrange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Profil auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VoiceConversionView()
        .environmentObject(VoiceProfileManager())
}
