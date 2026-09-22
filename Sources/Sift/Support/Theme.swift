import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.058)
    static let accentPrimary = Color(red: 0.42, green: 0.38, blue: 0.98)
    static let accentSecondary = Color(red: 0.16, green: 0.85, blue: 0.75)
    static let rarelyPlayed = Color(red: 0.20, green: 0.72, blue: 0.88)
    static let mostPlayed = Color(red: 0.95, green: 0.32, blue: 0.62)

    static let accentGradient = LinearGradient(
        colors: [accentSecondary, accentPrimary],
        startPoint: .leading,
        endPoint: .trailing
    )
}
