import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: VoiceProfileManager
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                progressIndicator

                Spacer()

                Group {
                    switch viewModel.currentStep {
                    case .naming:
                        namingStepView
                    case .recording:
                        recordingStepView
                    case .analyzing:
                        analyzingStepView
                    case .complete:
                        completeStepView
                    }
                }

                Spacer()

                navigationButtons
            }
            .padding()
            .background(Color.backgroundPrimary)
            .navigationTitle("Neues Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.setProfileManager(profileManager)
            }
            .alert("Fehler", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(ProfileCreationStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= viewModel.currentStep.rawValue ?
                          Color.accentPurple : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)

                if step != .complete {
                    Rectangle()
                        .fill(step.rawValue < viewModel.currentStep.rawValue ?
                              Color.accentPurple : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal)
    }

    private var namingStepView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.accentPurple)

            Text(viewModel.currentStep.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(viewModel.currentStep.description)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Profilname", text: $viewModel.profileName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var recordingStepView: some View {
        VStack(spacing: 24) {
            Text(viewModel.currentStep.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("Sample \(viewModel.recordedSamples.count + 1) von mindestens 3")
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            ProgressView(value: viewModel.recordingProgress)
                .tint(.accentPurple)
                .padding(.horizontal, 40)

            CircularWaveformView(
                audioLevel: viewModel.recordingService.audioLevel,
                isActive: viewModel.recordingService.recordingState == .recording
            )

            Text(viewModel.currentPrompt)
                .font(.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(12)

            HStack(spacing: 20) {
                if !viewModel.recordedSamples.isEmpty {
                    Button(action: { viewModel.deleteLastRecording() }) {
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
                        .frame(width: 80, height: 80)
                        .background(viewModel.recordingService.recordingState == .recording ?
                                    Color.errorRed : Color.accentPurple)
                        .cornerRadius(40)
                }

                if viewModel.recordingService.recordingURL != nil &&
                   viewModel.recordingService.recordingState != .recording {
                    Button(action: { viewModel.playLastRecording() }) {
                        Image(systemName: viewModel.recordingService.recordingState == .playing ?
                              "stop.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.accentPurple)
                            .frame(width: 50, height: 50)
                            .background(Color.backgroundSecondary)
                            .cornerRadius(25)
                    }
                }
            }

            if viewModel.recordingService.recordingState == .recording {
                Text(formatTime(viewModel.recordingService.currentTime))
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundColor(.accentPurple)
            }
        }
    }

    private var analyzingStepView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.accentPurple)

            Text(viewModel.currentStep.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(viewModel.currentStep.description)
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            Text("Bitte warten...")
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
    }

    private var completeStepView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.successGreen)

            Text(viewModel.currentStep.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(viewModel.currentStep.description)
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            if let profile = viewModel.createdProfile {
                VStack(spacing: 12) {
                    Text(profile.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 20) {
                        VStack {
                            Text("\(profile.totalSamples)")
                                .font(.headline)
                            Text("Samples")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Divider()
                            .frame(height: 30)

                        VStack {
                            Text(String(format: "%.0f Hz", profile.characteristics.averagePitch))
                                .font(.headline)
                            Text("Tonhöhe")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(12)
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if viewModel.currentStep != .naming && viewModel.currentStep != .analyzing {
                Button(action: { viewModel.previousStep() }) {
                    Text("Zurück")
                        .fontWeight(.medium)
                        .foregroundColor(.accentPurple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.backgroundSecondary)
                        .cornerRadius(12)
                }
            }

            if viewModel.currentStep == .complete {
                Button(action: {
                    if let profile = viewModel.createdProfile {
                        profileManager.setActiveProfile(profile)
                    }
                    viewModel.reset()
                    dismiss()
                }) {
                    Text("Fertig")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentPurple)
                        .cornerRadius(12)
                }
            } else if viewModel.currentStep != .analyzing {
                Button(action: { viewModel.nextStep() }) {
                    Text("Weiter")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canProceed ? Color.accentPurple : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!canProceed)
            }
        }
        .padding(.bottom)
    }

    private var canProceed: Bool {
        switch viewModel.currentStep {
        case .naming:
            return viewModel.canProceedFromNaming
        case .recording:
            return viewModel.canProceedFromRecording
        case .analyzing, .complete:
            return true
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    RecordingView()
        .environmentObject(VoiceProfileManager())
}
