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
}

/// Cursor-reactive Apple-glass surface: material + a soft prism highlight and rainbow
/// rim that track the mouse, like light catching a real glass edge as you move over it.
///
/// This replaces an earlier version driven by `TimelineView`, which redrew an
/// `AngularGradient` on every single display frame -- fine for a couple of buttons, but
/// once the same treatment sat on every row of a 1,000+ song track list, dozens of
/// on-screen rows were all animating every frame at once and it visibly lagged while
/// scrolling. Tracking `onContinuousHover` instead means a row only ever recomputes
/// when the mouse is actually over it, and everything else stays static.
private struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    let lineWidth: CGFloat
    @State private var hoverLocation: CGPoint?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        if let hoverLocation {
                            shape
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.55),
                                            Color(red: 1.0, green: 0.6, blue: 0.8).opacity(0.4),
                                            Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.26),
                                            .clear
                                        ],
                                        center: UnitPoint(
                                            x: geo.size.width > 0 ? hoverLocation.x / geo.size.width : 0.5,
                                            y: geo.size.height > 0 ? hoverLocation.y / geo.size.height : 0.5
                                        ),
                                        startRadius: 0,
                                        endRadius: max(geo.size.width, geo.size.height) * 0.7
                                    )
                                )
                                .blendMode(.plusLighter)
                        }
                    }
                }
            )
            .overlay(
                shape.stroke(
                    AngularGradient(
                        gradient: Gradient(colors: hoverLocation == nil
                            ? [
                                Color.white.opacity(0.3), Theme.accentSecondary.opacity(0.22),
                                Color.white.opacity(0.12), Color.white.opacity(0.3)
                            ]
                            : [
                                Color.white.opacity(0.9), Theme.accentSecondary.opacity(0.8),
                                Color(red: 0.6, green: 0.75, blue: 1.0).opacity(0.7),
                                Color.white.opacity(0.3), Color.white.opacity(0.9)
                            ]
                        ),
                        center: .center
                    ),
                    lineWidth: lineWidth
                )
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
            .animation(.easeOut(duration: 0.2), value: hoverLocation == nil)
    }
}

extension View {
    /// Applies the cursor-reactive glass surface (material + hover-tracking prism
    /// highlight + rainbow rim) to any shape -- buttons, cards, list rows, sheet chrome.
    func glassSurface<S: Shape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, lineWidth: lineWidth))
    }
}
