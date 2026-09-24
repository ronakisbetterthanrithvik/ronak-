import SwiftUI
import MusicKit

/// Crops `artwork` to fill an exact `size` x `size` square, edge to edge.
///
/// MusicKit's `ArtworkImage` only ever *fits* an image inside the width/height you give
/// it -- it preserves the artwork's own aspect ratio the way `.scaledToFit()` would,
/// and (being a plain `View`, not an `Image`) doesn't support `.resizable()` or
/// `.scaledToFill()` to override that. For any artwork that isn't already a perfect
/// square (very common for a custom photo someone set as their own playlist cover),
/// that leaves visible letterboxed gaps instead of filling the tile.
///
/// There's no supported "fill" mode to ask for instead, so this requests a deliberately
/// oversized rendition (2x the target size in both dimensions) and clips the overflow.
/// Since the fit calculation is bounded by whichever dimension is shorter, doubling both
/// guarantees full coverage on both axes for any photo up to a 2:1 (or 1:2) aspect ratio
/// -- comfortably past what a normal photo or screenshot ever is.
func squareArtwork(_ artwork: Artwork, size: CGFloat) -> some View {
    ArtworkImage(artwork, width: size * 2, height: size * 2)
        .frame(width: size, height: size)
        .clipped()
}
