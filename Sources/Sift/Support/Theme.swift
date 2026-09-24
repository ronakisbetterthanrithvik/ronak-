import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.058)

    // Vivid red/pink identity -- kept as a pure red spectrum (no orange cast) per the
    // reference swatch, deliberately distinct from Apple Music's own signature red since
    // this is a third-party app.
    static let accentPrimary = Color(red: 0.85, green: 0.06, blue: 0.20)
    static let accentSecondary = Color(red: 1.00, green: 0.28, blue: 0.42)
    static let rarelyPlayed = Color(red: 1.00, green: 0.55, blue: 0.60)
    static let mostPlayed = Color(red: 0.65, green: 0.03, blue: 0.14)

    static let accentGradient = LinearGradient(
        colors: [accentSecondary, accentPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Two or three of these, large and heavily blurred, sitting behind glass surfaces
    /// give Material something colorful to actually refract -- a flat black background
    /// makes .ultraThinMaterial read as plain dark gray instead of glass.
    static var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(accentPrimary.opacity(0.35))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -160, y: -220)
            Circle()
                .fill(accentSecondary.opacity(0.28))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: 220, y: 160)
        }
    }

    /// The glass fill: material plus a soft diagonal sheen, so surfaces catch light like
    /// a real glass pane instead of looking like a uniform tinted blur.
    static func glassFill<S: Shape>(_ shape: S) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    /// The glass rim: a gradient stroke, bright where light would catch the top-left edge
    /// and fading out toward the bottom-right, instead of a flat single-opacity outline.
    static func glassStroke<S: Shape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: lineWidth
        )
    }

    static func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return glassFill(shape).overlay(glassStroke(shape))
    }
}
