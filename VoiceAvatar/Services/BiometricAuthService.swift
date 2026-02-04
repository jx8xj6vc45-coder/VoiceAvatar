import LocalAuthentication
import SwiftUI

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "Nicht verfügbar"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "lock.slash"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

enum AuthenticationError: Error, LocalizedError {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case cancelled
    case failed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return "Biometrische Authentifizierung ist auf diesem Gerät nicht verfügbar"
        case .biometryNotEnrolled:
            return "Keine biometrischen Daten registriert. Bitte in den Einstellungen einrichten."
        case .biometryLockout:
            return "Biometrie ist gesperrt. Bitte Gerätecode verwenden."
        case .cancelled:
            return "Authentifizierung abgebrochen"
        case .failed:
            return "Authentifizierung fehlgeschlagen"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

@MainActor
class BiometricAuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAuthenticationEnabled, forKey: authEnabledKey)
        }
    }
    @Published var lastAuthenticationDate: Date?

    private let context = LAContext()
    private let authEnabledKey = "biometricAuthEnabled"
    private let authTimeoutSeconds: TimeInterval = 300

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    var isBiometricAvailable: Bool {
        biometricType != .none
    }

    var authenticationReason: String {
        "Entsperre VoiceAvatar, um auf deine Stimmprofile zuzugreifen"
    }

    init() {
        isAuthenticationEnabled = UserDefaults.standard.bool(forKey: authEnabledKey)
        checkAuthenticationTimeout()
    }

    func authenticate() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        context.localizedFallbackTitle = "Code verwenden"

        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                throw mapLAError(error)
            }
            throw AuthenticationError.biometryNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: authenticationReason
            )

            if success {
                isAuthenticated = true
                lastAuthenticationDate = Date()
            } else {
                throw AuthenticationError.failed
            }
        } catch let error as LAError {
            throw mapLAError(error)
        } catch {
            throw AuthenticationError.unknown(error)
        }
    }

    func authenticateWithFallback() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"

        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error = error {
                throw mapLAError(error)
            }
            throw AuthenticationError.biometryNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: authenticationReason
            )

            if success {
                isAuthenticated = true
                lastAuthenticationDate = Date()
            } else {
                throw AuthenticationError.failed
            }
        } catch let error as LAError {
            throw mapLAError(error)
        } catch {
            throw AuthenticationError.unknown(error)
        }
    }

    func logout() {
        isAuthenticated = false
        lastAuthenticationDate = nil
    }

    func checkAuthenticationTimeout() {
        guard let lastAuth = lastAuthenticationDate else {
            isAuthenticated = false
            return
        }

        let elapsed = Date().timeIntervalSince(lastAuth)
        if elapsed > authTimeoutSeconds {
            isAuthenticated = false
        }
    }

    var requiresAuthentication: Bool {
        isAuthenticationEnabled && !isAuthenticated
    }

    private func mapLAError(_ error: Error) -> AuthenticationError {
        guard let laError = error as? LAError else {
            return .unknown(error)
        }

        switch laError.code {
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLockout
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .authenticationFailed:
            return .failed
        default:
            return .unknown(error)
        }
    }
}
