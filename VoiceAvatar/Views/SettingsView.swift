import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var profileManager: VoiceProfileManager
    @EnvironmentObject var authService: BiometricAuthService

    @State private var showDeleteConfirmation = false
    @State private var showSecurityInfo = false

    var body: some View {
        NavigationStack {
            List {
                securitySection

                dataSection

                aboutSection
            }
            .navigationTitle("Einstellungen")
            .alert("Alle Daten löschen?", isPresented: $showDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    profileManager.deleteAllData()
                }
            } message: {
                Text("Alle Stimmprofile und Aufnahmen werden unwiderruflich gelöscht.")
            }
            .sheet(isPresented: $showSecurityInfo) {
                SecurityInfoView()
            }
        }
    }

    private var securitySection: some View {
        Section {
            if authService.isBiometricAvailable {
                Toggle(isOn: $authService.isAuthenticationEnabled) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("\(authService.biometricType.displayName) aktivieren")
                            Text("App beim Öffnen sperren")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    } icon: {
                        Image(systemName: authService.biometricType.iconName)
                            .foregroundColor(.accentPurple)
                    }
                }
                .tint(.accentPurple)
            } else {
                Label {
                    VStack(alignment: .leading) {
                        Text("Biometrie nicht verfügbar")
                        Text("Richte Face ID oder Touch ID in den Systemeinstellungen ein")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                } icon: {
                    Image(systemName: "faceid")
                        .foregroundColor(.gray)
                }
            }

            Button(action: { showSecurityInfo = true }) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Sicherheitsstatus")
                        Text(profileManager.securityStatus.isEmpty ? "Wird geladen..." : profileManager.securityStatus)
                            .font(.caption)
                            .foregroundColor(.successGreen)
                    }
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.successGreen)
                }
            }
            .foregroundColor(.textPrimary)
        } header: {
            Text("Sicherheit")
        } footer: {
            Text("Deine Stimmprofile werden verschlüsselt auf dem Gerät gespeichert und sind von iCloud-Backups ausgeschlossen.")
        }
    }

    private var dataSection: some View {
        Section {
            HStack {
                Label("Profile", systemImage: "person.wave.2.fill")
                Spacer()
                Text("\(profileManager.profiles.count)")
                    .foregroundColor(.textSecondary)
            }

            HStack {
                Label("Aufnahmen", systemImage: "waveform")
                Spacer()
                Text("\(totalSamples)")
                    .foregroundColor(.textSecondary)
            }

            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Label("Alle Daten löschen", systemImage: "trash.fill")
            }
        } header: {
            Text("Daten")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.textSecondary)
            }

            HStack {
                Label("Datenschutz", systemImage: "hand.raised.fill")
                Spacer()
                Text("Lokal & Sicher")
                    .foregroundColor(.successGreen)
            }
        } header: {
            Text("Über")
        } footer: {
            Text("VoiceAvatar speichert alle Daten ausschließlich lokal auf deinem Gerät. Keine Daten werden an Server übertragen.")
        }
    }

    private var totalSamples: Int {
        profileManager.profiles.reduce(0) { $0 + $1.totalSamples }
    }
}

struct SecurityInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: VoiceProfileManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecurityFeatureRow(
                        icon: "key.fill",
                        title: "Keychain-Speicherung",
                        description: "Profil-Metadaten werden im iOS Keychain gespeichert",
                        isEnabled: true
                    )

                    SecurityFeatureRow(
                        icon: "lock.fill",
                        title: "Data Protection",
                        description: "Audio-Dateien sind verschlüsselt wenn das Gerät gesperrt ist",
                        isEnabled: true
                    )

                    SecurityFeatureRow(
                        icon: "icloud.slash.fill",
                        title: "Backup-Ausschluss",
                        description: "Stimmprofile werden nicht in iCloud/iTunes gesichert",
                        isEnabled: true
                    )

                    SecurityFeatureRow(
                        icon: "faceid",
                        title: "Biometrische Sperre",
                        description: "App kann mit Face ID/Touch ID geschützt werden",
                        isEnabled: true
                    )
                } header: {
                    Text("Aktive Sicherheitsfeatures")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Was bedeutet das?")
                            .font(.headline)

                        Text("• Deine Stimmprofile verlassen niemals dein Gerät")
                            .font(.subheadline)

                        Text("• Ohne dein Gerät-Passwort kann niemand auf die Daten zugreifen")
                            .font(.subheadline)

                        Text("• Bei Geräteverlust sind die Daten durch die iOS-Verschlüsselung geschützt")
                            .font(.subheadline)

                        Text("• Selbst bei einem Backup werden deine Stimmprofile nicht übertragen")
                            .font(.subheadline)
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 4)
                } header: {
                    Text("Erklärung")
                }
            }
            .navigationTitle("Sicherheit")
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

struct SecurityFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isEnabled ? .successGreen : .gray)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isEnabled ? .successGreen : .errorRed)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(VoiceProfileManager())
        .environmentObject(BiometricAuthService())
}
