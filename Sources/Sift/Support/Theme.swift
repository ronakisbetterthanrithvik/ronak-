import SwiftUI
import AppKit

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.058)

    /// The pre-made frosted-glass Sift mark (`Resources/SiftIcon.png`), loaded by
    /// filename from the app bundle the way `NSImage(named:)` finds any loose bundled
    /// resource (it doesn't require an asset catalog). Falls back to a plain SF Symbol
    /// if the file hasn't been added to the Xcode target yet.
    static var appIcon: Image {
        if let nsImage = NSImage(named: "SiftIcon") {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "shuffle")
    }

    // Vivid red/pink identity -- kept as a pure red spectrum (no orange cast) per the
    // reference swatch, deliberately distinct from Apple Music's own signature red since
    // this is a third-party app.
    static let accentPrimary = Color(red: 0.85, green: 0.06, blue: 0.20)
    static let accentSecondary = Color(red: 1.00, green: 0.28, blue: 0.42)
    static let rarelyPlayed = Color(red: 1.00, green: 0.55, blue: 0.60)
    // A brighter, warmer red -- the previous shade (0.65, 0.03, 0.14) read as a muddy,
    // near-black maroon rather than a clear "most played" red.
    static let mostPlayed = Color(red: 1.00, green: 0.30, blue: 0.16)

    static let accentGradient = LinearGradient(
        colors: [accentSecondary, accentPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The same white/pink/cool-blue prism sequence used for the glass edge refraction
    /// (see `edgeGradient`), reused anywhere else that wants that "light catching glass"
    /// identity instead of the plain accent red -- the Familiarity slider's track, say.
    static let prismGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.9),
            accentSecondary,
            Color(red: 0.6, green: 0.75, blue: 1.0),
            Color.white.opacity(0.9)
        ],
        startPoint: .leading,
        endPoint: .trailing
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

    /// The rainbow rim itself -- only ever drawn as a thin stroke, never a fill, so the
    /// "refraction" reads as a highlight catching the glass's edge rather than a wash
    /// over the whole surface. The bright band sits at whichever angle the cursor
    /// currently is relative to the shape's center, so it visibly sweeps around the
    /// border as the mouse moves, and settles to a faint fixed highlight at rest.
    fileprivate static func edgeGradient(hoverLocation: CGPoint?, size: CGSize, baseOpacity: Double) -> AngularGradient {
        let angle: Angle = {
            guard let hoverLocation, size.width > 0, size.height > 0 else { return .degrees(135) }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            return Angle(radians: atan2(hoverLocation.y - center.y, hoverLocation.x - center.x))
        }()
        let peak = hoverLocation == nil ? baseOpacity + 0.18 : min(baseOpacity + 0.65, 0.95)
        let base = hoverLocation == nil ? baseOpacity : baseOpacity * 0.55

        // AngularGradient's `angle` marks location 0.0 of the stop list (not the
        // midpoint), so the bright band has to sit at 0.0/1.0 -- the two ends of the
        // list, which are adjacent on the circle since it wraps -- for the highlight to
        // actually land at `angle` instead of 180 degrees opposite it.
        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(peak), location: 0.0),
                .init(color: accentSecondary.opacity(peak * 0.85), location: 0.05),
                .init(color: Color(red: 0.6, green: 0.75, blue: 1.0).opacity(peak * 0.7), location: 0.1),
                .init(color: Color.white.opacity(base), location: 0.24),
                .init(color: Color.white.opacity(base), location: 0.76),
                .init(color: Color(red: 0.6, green: 0.75, blue: 1.0).opacity(peak * 0.7), location: 0.9),
                .init(color: accentSecondary.opacity(peak * 0.85), location: 0.95),
                .init(color: Color.white.opacity(peak), location: 1.0)
            ]),
            center: .center,
            angle: angle
        )
    }
}

/// Cursor-reactive Apple-glass surface: translucent `.ultraThinMaterial` (so whatever's
/// behind -- the dark background, the ambient glow -- still shows through) with a thin
/// rainbow rim along the edge only. The rim's bright point follows the cursor around the
/// border while it's hovering, and settles back to a faint, fixed highlight at rest.
///
/// Earlier versions filled the whole shape with an animated/hover-reactive gradient,
/// which (a) ran on every display frame via `TimelineView` and visibly lagged once it
/// sat on every row of a long track list, and (b) washed the surface out to a flat gray
/// instead of reading as glass. Confining all color to the stroke, driven only by
/// `onContinuousHover`, fixes both.
private struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    let lineWidth: CGFloat
    @State private var hoverLocation: CGPoint?

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(
                GeometryReader { geo in
                    shape.stroke(Theme.edgeGradient(hoverLocation: hoverLocation, size: geo.size, baseOpacity: 0.3), lineWidth: lineWidth)
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
            .animation(.easeOut(duration: 0.25), value: hoverLocation == nil)
    }
}

/// Same reactive rainbow rim as `glassSurface`, but with no fill of its own -- for rows
/// inside a container that already provides the translucent material (a track list, a
/// queue), so the black background shows straight through each row and only the border
/// catches light.
private struct GlassEdgeModifier<S: Shape>: ViewModifier {
    let shape: S
    let lineWidth: CGFloat
    let baseOpacity: Double
    @State private var hoverLocation: CGPoint?

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    shape.stroke(Theme.edgeGradient(hoverLocation: hoverLocation, size: geo.size, baseOpacity: baseOpacity), lineWidth: lineWidth)
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
            .animation(.easeOut(duration: 0.25), value: hoverLocation == nil)
    }
}

extension View {
    /// Full glass surface: translucent material fill + a hover-reactive rainbow edge.
    /// For standalone elements -- buttons, cards, sheet chrome.
    func glassSurface<S: Shape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, lineWidth: lineWidth))
    }

    /// Edge-only glass: a hover-reactive rainbow rim with no fill of its own. For rows
    /// that sit inside an already-translucent container.
    func glassEdge<S: Shape>(_ shape: S, lineWidth: CGFloat = 0.75, baseOpacity: Double = 0.32) -> some View {
        modifier(GlassEdgeModifier(shape: shape, lineWidth: lineWidth, baseOpacity: baseOpacity))
    }
}
