import SwiftUI

struct ProfileDetailView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    let profile: VoiceProfile

    @State private var showEditName = false
    @State private var editedName: String = ""

    private var currentProfile: VoiceProfile {
        profileManager.profiles.first { $0.id == profile.id } ?? profile
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeader

                characteristicsSection

                samplesSection

                actionsSection

                Spacer(minLength: 50)
            }
            .padding()
        }
        .background(Color.backgroundPrimary)
        .navigationTitle(currentProfile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showEditName = true }) {
                        Label("Umbenennen", systemImage: "pencil")
                    }

                    Button(action: { profileManager.setActiveProfile(currentProfile) }) {
                        Label("Als aktiv setzen", systemImage: "checkmark.circle")
                    }

                    Divider()

                    Button(role: .destructive, action: { viewModel.confirmDelete(currentProfile) }) {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.accentPurple)
                }
            }
        }
        .alert("Profil umbenennen", isPresented: $showEditName) {
            TextField("Name", text: $editedName)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                var updated = currentProfile
                updated.name = editedName
                profileManager.updateProfile(updated)
            }
        }
        .alert("Profil löschen?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                profileManager.deleteProfile(currentProfile)
                dismiss()
            }
        } message: {
            Text("Diese Aktion kann nicht rückgängig gemacht werden.")
        }
        .onAppear {
            editedName = currentProfile.name
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentPurple, .accentPurpleLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text(currentProfile.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if currentProfile.isActive {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.successGreen)
                        Text("Aktives Profil")
                            .foregroundColor(.successGreen)
                    }
                    .font(.subheadline)
                }
            }

            HStack(spacing: 24) {
                StatBubble(
                    value: "\(currentProfile.totalSamples)",
                    label: "Samples",
                    color: currentProfile.hasEnoughSamples ? .successGreen : .warningOrange
                )

                StatBubble(
                    value: viewModel.formatDate(currentProfile.createdAt),
                    label: "Erstellt",
                    color: .accentPurple
                )
            }
        }
    }

    private var characteristicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stimmcharakteristik")
                .font(.headline)

            VStack(spacing: 12) {
                CharacteristicRow(
                    icon: "waveform",
                    title: "Durchschnittliche Tonhöhe",
                    value: "\(Int(currentProfile.characteristics.averagePitch)) Hz"
                )

                CharacteristicRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Tonhöhenvarianz",
                    value: "\(Int(currentProfile.characteristics.pitchVariance)) Hz"
                )

                CharacteristicRow(
                    icon: "speaker.wave.3.fill",
                    title: "Durchschnittliche Energie",
                    value: viewModel.formatCharacteristic(currentProfile.characteristics.averageEnergy)
                )

                CharacteristicRow(
                    icon: "speedometer",
                    title: "Sprechgeschwindigkeit",
                    value: "\(Int(currentProfile.characteristics.speakingRate)) Silben/Min"
                )

                CharacteristicRow(
                    icon: "waveform.path.ecg",
                    title: "Spektraler Schwerpunkt",
                    value: "\(Int(currentProfile.characteristics.spectralCentroid)) Hz"
                )
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(12)
        }
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aufnahmen")
                    .font(.headline)

                Spacer()

                if !currentProfile.hasEnoughSamples {
                    Text("Min. 3 benötigt")
                        .font(.caption)
                        .foregroundColor(.warningOrange)
                }
            }

            if currentProfile.sampleURLs.isEmpty {
                Text("Keine Aufnahmen vorhanden")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color.backgroundSecondary)
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(currentProfile.sampleURLs.enumerated()), id: \.offset) { index, url in
                        SampleRow(
                            index: index + 1,
                            isPlaying: viewModel.isPlayingSample && viewModel.currentSampleIndex == index,
                            onPlay: { viewModel.playSample(at: index, from: currentProfile) },
                            onStop: { viewModel.stopPlayback() },
                            onDelete: { profileManager.removeSampleFromProfile(currentProfile.id, at: index) }
                        )
                    }
                }
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(12)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if !currentProfile.isActive {
                Button(action: { profileManager.setActiveProfile(currentProfile) }) {
                    Label("Als aktives Profil setzen", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentPurple)
                        .cornerRadius(12)
                }
            }

            NavigationLink {
                VoiceConversionView()
            } label: {
                Label("Stimme konvertieren", systemImage: "waveform.circle.fill")
                    .font(.headline)
                    .foregroundColor(.accentPurple)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.backgroundSecondary)
                    .cornerRadius(12)
            }
        }
    }
}

struct StatBubble: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct CharacteristicRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentPurple)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct SampleRow: View {
    let index: Int
    let isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("Sample \(index)")
                .font(.subheadline)

            Spacer()

            Button(action: isPlaying ? onStop : onPlay) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentPurple)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundColor(.errorRed)
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ProfileDetailView(profile: VoiceProfile(
            name: "Test Profil",
            sampleURLs: [],
            characteristics: VoiceCharacteristics(
                averagePitch: 180,
                pitchVariance: 25,
                averageEnergy: 0.4,
                speakingRate: 120,
                spectralCentroid: 1200
            )
        ))
    }
    .environmentObject(VoiceProfileManager())
}
