import SwiftUI

extension Color {
    static let accentPurple = Color(red: 0.4, green: 0.2, blue: 0.8)
    static let accentPurpleLight = Color(red: 0.6, green: 0.4, blue: 0.9)
    static let accentPurpleDark = Color(red: 0.3, green: 0.1, blue: 0.6)

    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    static let backgroundTertiary = Color(UIColor.tertiarySystemBackground)

    static let textPrimary = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary = Color(UIColor.tertiaryLabel)

    static let successGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let errorRed = Color(red: 0.9, green: 0.3, blue: 0.3)

    static let waveformActive = Color.accentPurple
    static let waveformInactive = Color.gray.opacity(0.3)

    static let gradientStart = Color.accentPurple
    static let gradientEnd = Color.accentPurpleLight
}

extension LinearGradient {
    static let primaryGradient = LinearGradient(
        colors: [.gradientStart, .gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color.backgroundPrimary, Color.backgroundSecondary],
        startPoint: .top,
        endPoint: .bottom
    )
}
