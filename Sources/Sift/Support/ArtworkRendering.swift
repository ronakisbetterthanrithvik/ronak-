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
/// There's no supported "fill" mode to ask for instead, so this requests a somewhat
/// oversized rendition and clips the overflow. `overscan` controls by how much:
/// - Real album/song artwork (the default call site) is always exactly square in
///   practice, so it needs no safety margin at all -- asking for 2x here was needless
///   and, multiplied across every row of a 1,000+ song track list while scrolling, was
///   enough extra network load to cause real timeouts and rows stuck on a broken tile.
/// - A personal playlist's own custom cover, though, can be any photo a person picked,
///   so those call sites should still pass a taller `overscan` (2.0 comfortably covers
///   any photo up to a 2:1 aspect ratio) to guarantee full coverage.
func squareArtwork(_ artwork: Artwork, size: CGFloat, overscan: CGFloat = 1.0) -> some View {
    ArtworkImage(artwork, width: size * overscan, height: size * overscan)
        .frame(width: size, height: size)
        .clipped()
}
