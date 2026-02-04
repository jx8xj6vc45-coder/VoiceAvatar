import Foundation

class SecurityManager {
    static let shared = SecurityManager()

    private let fileManager = FileManager.default

    private init() {}

    func secureFile(at url: URL) throws {
        try setDataProtection(for: url)
        try excludeFromBackup(url: url)
    }

    func secureDirectory(at url: URL) throws {
        try setDataProtection(for: url)
        try excludeFromBackup(url: url)

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )

        for item in contents {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    try secureDirectory(at: item)
                } else {
                    try secureFile(at: item)
                }
            }
        }
    }

    private func setDataProtection(for url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
    }

    private func excludeFromBackup(url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true

        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    func createSecureDirectory(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUnlessOpen
                ]
            )
        }
        try excludeFromBackup(url: url)
    }

    func secureMove(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
        try secureFile(at: destination)
        try fileManager.removeItem(at: source)
    }

    func secureCopy(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
        try secureFile(at: destination)
    }

    func secureDelete(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func isFileProtected(at url: URL) -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let protection = attributes[.protectionKey] as? FileProtectionType {
                return protection == .complete ||
                       protection == .completeUnlessOpen ||
                       protection == .completeUntilFirstUserAuthentication
            }
        } catch {
            return false
        }
        return false
    }

    func isExcludedFromBackup(url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            return resourceValues.isExcludedFromBackup ?? false
        } catch {
            return false
        }
    }

    func getSecurityStatus(for url: URL) -> SecurityStatus {
        SecurityStatus(
            isProtected: isFileProtected(at: url),
            isExcludedFromBackup: isExcludedFromBackup(url: url),
            exists: fileManager.fileExists(atPath: url.path)
        )
    }
}

struct SecurityStatus {
    let isProtected: Bool
    let isExcludedFromBackup: Bool
    let exists: Bool

    var isFullySecured: Bool {
        isProtected && isExcludedFromBackup && exists
    }

    var description: String {
        var status: [String] = []
        if isProtected {
            status.append("Verschlüsselt")
        }
        if isExcludedFromBackup {
            status.append("Backup ausgeschlossen")
        }
        return status.isEmpty ? "Nicht gesichert" : status.joined(separator: ", ")
    }
}
