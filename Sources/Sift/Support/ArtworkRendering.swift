import SwiftUI
import MusicKit

/// Crops `artwork` to fill an exact `size` x `size` square, edge to edge.
///
/// MusicKit's `ArtworkImage` only ever *fits* an image inside the width/height you give
/// it -- it preserves the artwork's own aspect ratio the way `.scaledToFit()` would,
/// and (being a plain `View`, not an `Image`) doesn't support `.resizable()` or
/// `.scaledToFill()` to override that. For any artwork that isn't already a perfect
/// square (a custom photo someone set as their own playlist cover, say), that leaves
/// visible letterboxed gaps instead of filling the tile.
///
/// There's no supported "fill" mode to ask for instead, so this requests a box shaped
/// like the artwork's own real aspect ratio (from `artwork.maximumWidth`/
/// `maximumHeight`, which come free with the `Artwork` value -- no network round trip)
/// whose *short* edge equals `size`. Fitting the artwork into that box already fills the
/// square completely on the short axis with zero letterboxing, and only overflows (for
/// `.clipped()` to trim) on the long axis, centered -- exactly a CSS `object-fit: cover`,
/// rather than the flat guessed multiplier this used before, which either over-cropped a
/// near-square photo or under-covered a very wide/tall one depending on how far off the
/// guess was.
///
/// `overscan` is an optional extra safety margin on top of that (1.0 = none) for a
/// source whose real dimensions might not be trustworthy.
func squareArtwork(_ artwork: Artwork, size: CGFloat, overscan: CGFloat = 1.0) -> some View {
    let request = coverRequestSize(for: artwork, targetSize: size, overscan: overscan)
    return ArtworkImage(artwork, width: request.width, height: request.height)
        .frame(width: size, height: size)
        .clipped()
}

private func coverRequestSize(for artwork: Artwork, targetSize: CGFloat, overscan: CGFloat) -> (width: CGFloat, height: CGFloat) {
    guard artwork.maximumWidth > 0, artwork.maximumHeight > 0 else {
        // No usable dimensions to compute a precise cover box from -- fall back to the
        // old flat-multiple guess rather than requesting a degenerate/zero-size image.
        let fallback = targetSize * max(overscan, 1.5)
        return (fallback, fallback)
    }
    let aspect = CGFloat(artwork.maximumWidth) / CGFloat(artwork.maximumHeight)
    let base: (width: CGFloat, height: CGFloat) = aspect >= 1
        ? (targetSize * aspect, targetSize)
        : (targetSize, targetSize / aspect)
    return (base.width * overscan, base.height * overscan)
}
