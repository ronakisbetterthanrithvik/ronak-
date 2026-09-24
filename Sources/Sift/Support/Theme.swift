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

    /// A couple of soft, localized blurred shapes near the header -- just enough for
    /// glass surfaces nearby to have something colorful to refract, without washing the
    /// whole window in color the way a larger/brighter version did.
    static var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(accentPrimary.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(x: -180, y: -200)
            Circle()
                .fill(accentSecondary.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 140)
                .offset(x: 220, y: -40)
        }
    }

    /// A thin diagonal iridescent streak that continuously sweeps across the surface --
    /// white catching the light, then a hint of pink and cool blue -- like a prism edge
    /// on real glass. Driven by `TimelineView` so it's genuinely animated, not a static
    /// gradient. Blended additively so it brightens rather than muddying what's underneath.
    static func prismSheen<S: Shape>(_ shape: S) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(t / 1.8) + 1) / 2 // oscillates 0...1

            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.22)),
                            .init(color: Color.white.opacity(0.45), location: phase),
                            .init(color: Color(red: 1.0, green: 0.6, blue: 0.8).opacity(0.34), location: min(1, phase + 0.08)),
                            .init(color: Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.26), location: min(1, phase + 0.16)),
                            .init(color: .clear, location: min(1, phase + 0.34))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
        }
    }

    /// A rotating rainbow-tinted rim, like light catching a glass edge from different
    /// angles -- also `TimelineView`-driven, so the color genuinely shifts over time
    /// instead of sitting as one fixed gradient.
    static func glassStroke<S: Shape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle(degrees: t.truncatingRemainder(dividingBy: 8) / 8 * 360)

            shape.stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.75),
                        accentSecondary.opacity(0.65),
                        Color(red: 0.6, green: 0.75, blue: 1.0).opacity(0.55),
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.75)
                    ]),
                    center: .center,
                    angle: angle
                ),
                lineWidth: lineWidth
            )
        }
    }

    /// The glass fill: material, a soft directional highlight, and the animated prism
    /// streak layered together so surfaces catch light like a real glass pane.
    static func glassFill<S: Shape>(_ shape: S) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            prismSheen(shape)
        }
    }

    static func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return glassFill(shape).overlay(glassStroke(shape, lineWidth: 1.25))
    }
}
