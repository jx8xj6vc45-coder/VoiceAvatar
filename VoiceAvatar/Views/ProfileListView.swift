import SwiftUI

struct ProfileListView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showCreateProfile = false

    var body: some View {
        NavigationStack {
            Group {
                if profileManager.profiles.isEmpty {
                    emptyStateView
                } else {
                    profilesList
                }
            }
            .navigationTitle("Stimmprofile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateProfile = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentPurple)
                    }
                }
            }
            .sheet(isPresented: $showCreateProfile) {
                RecordingView()
            }
            .alert("Profil löschen?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    if let profile = viewModel.profileToDelete {
                        profileManager.deleteProfile(profile)
                    }
                }
            } message: {
                if let profile = viewModel.profileToDelete {
                    Text("Möchtest du '\(profile.name)' wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 60))
                .foregroundColor(.textTertiary)

            Text("Keine Profile vorhanden")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Erstelle dein erstes Stimmprofil, um loszulegen")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: { showCreateProfile = true }) {
                Label("Profil erstellen", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentPurple)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
        .padding()
    }

    private var profilesList: some View {
        List {
            ForEach(profileManager.profiles) { profile in
                NavigationLink {
                    ProfileDetailView(profile: profile)
                } label: {
                    ProfileListRow(
                        profile: profile,
                        isActive: profile.id == profileManager.activeProfile?.id
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.confirmDelete(profile)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }

                    Button {
                        profileManager.setActiveProfile(profile)
                    } label: {
                        Label("Aktivieren", systemImage: "checkmark.circle")
                    }
                    .tint(.accentPurple)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ProfileListRow: View {
    let profile: VoiceProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentPurple : Color.backgroundSecondary)
                    .frame(width: 50, height: 50)

                Image(systemName: "person.wave.2.fill")
                    .font(.title3)
                    .foregroundColor(isActive ? .white : .accentPurple)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.headline)

                    if isActive {
                        Text("Aktiv")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.successGreen)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Label("\(profile.totalSamples) Samples", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    Text("•")
                        .foregroundColor(.textTertiary)

                    Text(formatDate(profile.createdAt))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            if profile.hasEnoughSamples {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.successGreen)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.warningOrange)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}

#Preview {
    ProfileListView()
        .environmentObject(VoiceProfileManager())
}
