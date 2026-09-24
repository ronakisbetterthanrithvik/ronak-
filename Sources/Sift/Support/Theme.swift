import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.058)

    // Rose/coral identity -- deliberately not Apple Music's exact red, since this is a
    // third-party app and the PRD calls for its own visual identity.
    static let accentPrimary = Color(red: 0.86, green: 0.17, blue: 0.32)
    static let accentSecondary = Color(red: 0.98, green: 0.53, blue: 0.42)
    static let rarelyPlayed = Color(red: 0.98, green: 0.68, blue: 0.58)
    static let mostPlayed = Color(red: 0.70, green: 0.09, blue: 0.22)

    static let accentGradient = LinearGradient(
        colors: [accentSecondary, accentPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A subtle frosted-glass card background: material for the "liquid glass" feel,
    /// plus a thin highlight edge so panels read as glass rather than flat gray boxes.
    static func glassCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
