import Foundation
import Combine

@MainActor
class VoiceProfileManager: ObservableObject {
    @Published var profiles: [VoiceProfile] = []
    @Published var activeProfile: VoiceProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var securityStatus: String = ""

    private let profilesKey = "voiceProfiles"
    private let activeProfileKey = "activeProfileId"
    private let fileManager = FileManager.default
    private let securityManager = SecurityManager.shared
    private let keychainService = KeychainService.shared

    private var useKeychain: Bool = true

    init() {
        loadProfiles()
        Task {
            await secureExistingData()
        }
    }

    var profilesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let profilesPath = documentsPath.appendingPathComponent("VoiceProfiles", isDirectory: true)
        if !fileManager.fileExists(atPath: profilesPath.path) {
            try? securityManager.createSecureDirectory(at: profilesPath)
        }
        return profilesPath
    }

    func createProfile(name: String) -> VoiceProfile {
        let profile = VoiceProfile(name: name)
        let profileDirectory = profilesDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)

        do {
            try securityManager.createSecureDirectory(at: profileDirectory)
        } catch {
            errorMessage = "Fehler beim Erstellen des sicheren Verzeichnisses: \(error.localizedDescription)"
        }

        profiles.append(profile)
        saveProfiles()
        return profile
    }

    func updateProfile(_ profile: VoiceProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if activeProfile?.id == profile.id {
                activeProfile = profile
            }
            saveProfiles()
        }
    }

    func deleteProfile(_ profile: VoiceProfile) {
        let profileDirectory = profilesDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)

        do {
            try securityManager.secureDelete(at: profileDirectory)
        } catch {
            try? fileManager.removeItem(at: profileDirectory)
        }

        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = nil
        }
        saveProfiles()
    }

    func setActiveProfile(_ profile: VoiceProfile?) {
        for i in profiles.indices {
            profiles[i].isActive = profiles[i].id == profile?.id
        }
        activeProfile = profile
        saveProfiles()
    }

    func addSampleToProfile(_ profileId: UUID, sampleURL: URL) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }

        let profileDirectory = profilesDirectory.appendingPathComponent(profileId.uuidString, isDirectory: true)
        let sampleFilename = "sample_\(profiles[index].sampleURLs.count + 1).m4a"
        let destinationURL = profileDirectory.appendingPathComponent(sampleFilename)

        do {
            try securityManager.secureCopy(from: sampleURL, to: destinationURL)
            profiles[index].addSample(destinationURL)
            saveProfiles()
        } catch {
            errorMessage = "Fehler beim sicheren Speichern: \(error.localizedDescription)"
        }
    }

    func removeSampleFromProfile(_ profileId: UUID, at sampleIndex: Int) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }),
              sampleIndex < profiles[profileIndex].sampleURLs.count else { return }

        let sampleURL = profiles[profileIndex].sampleURLs[sampleIndex]

        do {
            try securityManager.secureDelete(at: sampleURL)
        } catch {
            try? fileManager.removeItem(at: sampleURL)
        }

        profiles[profileIndex].removeSample(at: sampleIndex)
        saveProfiles()
    }

    func getProfileDirectory(for profileId: UUID) -> URL {
        return profilesDirectory.appendingPathComponent(profileId.uuidString, isDirectory: true)
    }

    func getSecurityStatus() -> (encrypted: Int, total: Int) {
        var encrypted = 0
        var total = 0

        for profile in profiles {
            for url in profile.sampleURLs {
                total += 1
                if securityManager.isFileProtected(at: url) {
                    encrypted += 1
                }
            }
        }

        return (encrypted, total)
    }

    private func secureExistingData() async {
        do {
            try securityManager.secureDirectory(at: profilesDirectory)
            let status = getSecurityStatus()
            securityStatus = "\(status.encrypted)/\(status.total) Dateien gesichert"
        } catch {
            securityStatus = "Sicherung fehlgeschlagen"
        }
    }

    private func loadProfiles() {
        if useKeychain {
            loadFromKeychain()
        } else {
            loadFromUserDefaults()
        }
    }

    private func loadFromKeychain() {
        do {
            let decoded: [VoiceProfile] = try keychainService.load(forKey: profilesKey)
            profiles = decoded

            let activeId: String = try keychainService.load(forKey: activeProfileKey)
            if let uuid = UUID(uuidString: activeId),
               let profile = profiles.first(where: { $0.id == uuid }) {
                activeProfile = profile
            }
        } catch KeychainError.notFound {
            loadFromUserDefaults()
            if !profiles.isEmpty {
                migrateToKeychain()
            }
        } catch {
            loadFromUserDefaults()
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([VoiceProfile].self, from: data) else {
            return
        }
        profiles = decoded

        if let activeId = UserDefaults.standard.string(forKey: activeProfileKey),
           let uuid = UUID(uuidString: activeId),
           let profile = profiles.first(where: { $0.id == uuid }) {
            activeProfile = profile
        }
    }

    private func migrateToKeychain() {
        do {
            try keychainService.save(profiles, forKey: profilesKey)
            if let activeId = activeProfile?.id.uuidString {
                try keychainService.save(activeId, forKey: activeProfileKey)
            }

            UserDefaults.standard.removeObject(forKey: profilesKey)
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        } catch {
            errorMessage = "Migration zu Keychain fehlgeschlagen"
        }
    }

    private func saveProfiles() {
        if useKeychain {
            saveToKeychain()
        } else {
            saveToUserDefaults()
        }
    }

    private func saveToKeychain() {
        do {
            try keychainService.save(profiles, forKey: profilesKey)

            if let activeId = activeProfile?.id.uuidString {
                try keychainService.save(activeId, forKey: activeProfileKey)
            } else {
                try keychainService.delete(forKey: activeProfileKey)
            }
        } catch {
            saveToUserDefaults()
            errorMessage = "Keychain-Speicherung fehlgeschlagen, UserDefaults verwendet"
        }
    }

    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }

        if let activeId = activeProfile?.id.uuidString {
            UserDefaults.standard.set(activeId, forKey: activeProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }
    }

    func deleteAllData() {
        for profile in profiles {
            let profileDirectory = profilesDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)
            try? fileManager.removeItem(at: profileDirectory)
        }

        profiles.removeAll()
        activeProfile = nil

        try? keychainService.delete(forKey: profilesKey)
        try? keychainService.delete(forKey: activeProfileKey)
        UserDefaults.standard.removeObject(forKey: profilesKey)
        UserDefaults.standard.removeObject(forKey: activeProfileKey)
    }
}
