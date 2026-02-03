import SwiftUI

struct HomeView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @State private var showCreateProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if let activeProfile = profileManager.activeProfile {
                        activeProfileCard(activeProfile)
                    } else {
                        noActiveProfileCard
                    }

                    quickActionsSection

                    if !profileManager.profiles.isEmpty {
                        recentProfilesSection
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Voice Avatar")
            .sheet(isPresented: $showCreateProfile) {
                RecordingView()
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.linearGradient(
                    colors: [.accentPurple, .accentPurpleLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Willkommen")
                .font(.title)
                .fontWeight(.bold)

            Text("Erstelle Stimmprofile und transformiere deine Stimme")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private func activeProfileCard(_ profile: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.wave.2.fill")
                    .font(.title2)
                    .foregroundColor(.accentPurple)

                VStack(alignment: .leading) {
                    Text("Aktives Profil")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(profile.name)
                        .font(.headline)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.successGreen)
            }

            Divider()

            HStack {
                ProfileStatView(
                    icon: "mic.fill",
                    value: "\(profile.totalSamples)",
                    label: "Samples"
                )

                Spacer()

                ProfileStatView(
                    icon: "waveform",
                    value: String(format: "%.0f Hz", profile.characteristics.averagePitch),
                    label: "Tonhöhe"
                )

                Spacer()

                ProfileStatView(
                    icon: "clock.fill",
                    value: formatDate(profile.updatedAt),
                    label: "Aktualisiert"
                )
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }

    private var noActiveProfileCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.textTertiary)

            Text("Kein aktives Profil")
                .font(.headline)

            Text("Erstelle ein Stimmprofil, um loszulegen")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: { showCreateProfile = true }) {
                Label("Profil erstellen", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentPurple)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schnellaktionen")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "plus.circle.fill",
                    title: "Neues Profil",
                    color: .accentPurple
                ) {
                    showCreateProfile = true
                }

                NavigationLink {
                    VoiceConversionView()
                } label: {
                    QuickActionCard(
                        icon: "waveform.circle.fill",
                        title: "Konvertieren",
                        color: .accentPurpleLight
                    )
                }
            }
        }
    }

    private var recentProfilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Deine Profile")
                    .font(.headline)

                Spacer()

                NavigationLink {
                    ProfileListView()
                } label: {
                    Text("Alle anzeigen")
                        .font(.subheadline)
                        .foregroundColor(.accentPurple)
                }
            }

            ForEach(profileManager.profiles.prefix(3)) { profile in
                ProfileRowView(profile: profile) {
                    profileManager.setActiveProfile(profile)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ProfileStatView: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentPurple)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionCard(icon: icon, title: title, color: color)
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

struct ProfileRowView: View {
    let profile: VoiceProfile
    let onSelect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.accentPurple)

            VStack(alignment: .leading) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(profile.totalSamples) Samples")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            if profile.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.successGreen)
            } else {
                Button("Aktivieren") {
                    onSelect()
                }
                .font(.caption)
                .foregroundColor(.accentPurple)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
        .environmentObject(VoiceProfileManager())
}
