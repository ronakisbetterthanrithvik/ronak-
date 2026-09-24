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

    /// Large, heavily blurred shapes sitting behind glass surfaces so Material has
    /// something colorful to actually refract -- spread across the whole scroll area
    /// (not just near the header), since a card further down with nothing colorful
    /// behind it just reads as plain dark gray.
    static var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(accentPrimary.opacity(0.4))
                .frame(width: 620, height: 620)
                .blur(radius: 160)
                .offset(x: -220, y: -260)
            Circle()
                .fill(accentSecondary.opacity(0.32))
                .frame(width: 560, height: 560)
                .blur(radius: 160)
                .offset(x: 260, y: -60)
            Circle()
                .fill(accentPrimary.opacity(0.3))
                .frame(width: 560, height: 560)
                .blur(radius: 160)
                .offset(x: -180, y: 480)
            Circle()
                .fill(mostPlayed.opacity(0.26))
                .frame(width: 520, height: 520)
                .blur(radius: 160)
                .offset(x: 260, y: 760)
        }
    }

    /// A thin diagonal iridescent streak -- white catching the light, then a hint of
    /// pink and cool blue as it fades -- like a prism edge on real glass. Blended
    /// additively so it brightens rather than muddying whatever's underneath.
    static func prismSheen<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.white.opacity(0.0), location: 0.32),
                        .init(color: Color.white.opacity(0.4), location: 0.44),
                        .init(color: Color(red: 1.0, green: 0.6, blue: 0.78).opacity(0.32), location: 0.52),
                        .init(color: Color(red: 0.55, green: 0.7, blue: 1.0).opacity(0.26), location: 0.6),
                        .init(color: .clear, location: 0.74),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
    }

    /// The glass fill: material, a soft directional sheen, and a prism streak layered
    /// together so surfaces catch light like a real glass pane.
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
            prismSheen(shape)
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
