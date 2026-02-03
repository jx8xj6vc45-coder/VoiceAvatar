import Foundation
import Combine

@MainActor
class VoiceProfileManager: ObservableObject {
    @Published var profiles: [VoiceProfile] = []
    @Published var activeProfile: VoiceProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let profilesKey = "voiceProfiles"
    private let activeProfileKey = "activeProfileId"
    private let fileManager = FileManager.default

    init() {
        loadProfiles()
    }

    var profilesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let profilesPath = documentsPath.appendingPathComponent("VoiceProfiles", isDirectory: true)
        if !fileManager.fileExists(atPath: profilesPath.path) {
            try? fileManager.createDirectory(at: profilesPath, withIntermediateDirectories: true)
        }
        return profilesPath
    }

    func createProfile(name: String) -> VoiceProfile {
        let profile = VoiceProfile(name: name)
        let profileDirectory = profilesDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

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
        try? fileManager.removeItem(at: profileDirectory)

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
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sampleURL, to: destinationURL)
            profiles[index].addSample(destinationURL)
            saveProfiles()
        } catch {
            errorMessage = "Failed to save sample: \(error.localizedDescription)"
        }
    }

    func removeSampleFromProfile(_ profileId: UUID, at sampleIndex: Int) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }),
              sampleIndex < profiles[profileIndex].sampleURLs.count else { return }

        let sampleURL = profiles[profileIndex].sampleURLs[sampleIndex]
        try? fileManager.removeItem(at: sampleURL)
        profiles[profileIndex].removeSample(at: sampleIndex)
        saveProfiles()
    }

    func getProfileDirectory(for profileId: UUID) -> URL {
        return profilesDirectory.appendingPathComponent(profileId.uuidString, isDirectory: true)
    }

    private func loadProfiles() {
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

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }

        if let activeId = activeProfile?.id.uuidString {
            UserDefaults.standard.set(activeId, forKey: activeProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }
    }
}
