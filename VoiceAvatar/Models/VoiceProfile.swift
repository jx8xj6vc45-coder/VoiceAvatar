import Foundation

struct VoiceProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sampleURLs: [URL]
    var characteristics: VoiceCharacteristics
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sampleURLs: [URL] = [],
        characteristics: VoiceCharacteristics = VoiceCharacteristics(),
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sampleURLs = sampleURLs
        self.characteristics = characteristics
        self.isActive = isActive
    }

    var totalSamples: Int {
        sampleURLs.count
    }

    var hasEnoughSamples: Bool {
        sampleURLs.count >= 3
    }

    mutating func addSample(_ url: URL) {
        sampleURLs.append(url)
        updatedAt = Date()
    }

    mutating func removeSample(at index: Int) {
        guard index < sampleURLs.count else { return }
        sampleURLs.remove(at: index)
        updatedAt = Date()
    }
}

struct VoiceCharacteristics: Codable, Equatable {
    var averagePitch: Float
    var pitchVariance: Float
    var averageEnergy: Float
    var speakingRate: Float
    var spectralCentroid: Float
    var formantFrequencies: [Float]

    init(
        averagePitch: Float = 0,
        pitchVariance: Float = 0,
        averageEnergy: Float = 0,
        speakingRate: Float = 0,
        spectralCentroid: Float = 0,
        formantFrequencies: [Float] = []
    ) {
        self.averagePitch = averagePitch
        self.pitchVariance = pitchVariance
        self.averageEnergy = averageEnergy
        self.speakingRate = speakingRate
        self.spectralCentroid = spectralCentroid
        self.formantFrequencies = formantFrequencies
    }
}

enum ProfileCreationStep: Int, CaseIterable {
    case naming = 0
    case recording = 1
    case analyzing = 2
    case complete = 3

    var title: String {
        switch self {
        case .naming: return "Profil benennen"
        case .recording: return "Stimme aufnehmen"
        case .analyzing: return "Analyse"
        case .complete: return "Fertig"
        }
    }

    var description: String {
        switch self {
        case .naming: return "Gib deinem Stimmprofil einen Namen"
        case .recording: return "Nimm mindestens 3 Samples auf"
        case .analyzing: return "Deine Stimme wird analysiert..."
        case .complete: return "Dein Stimmprofil ist bereit!"
        }
    }
}
