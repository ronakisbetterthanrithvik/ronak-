import SwiftUI
import AppKit

/// An Instagram-style "reposition and zoom" cropper for a playlist's custom cover photo
/// -- drag to pan, pinch (trackpad) to zoom, confirm to bake exactly what's inside the
/// square frame into a new image, instead of always using whatever `squareArtwork`'s
/// automatic center-crop would have picked.
struct ImageCropPickerView: View {
    let image: NSImage
    var onConfirm: (NSImage) -> Void
    var onCancel: () -> Void

    private let viewportSize: CGFloat = 280
    private let maxZoom: CGFloat = 4

    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    private var imageSize: CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return CGSize(width: 1, height: 1) }
        return image.size
    }

    /// The scale at which the image, undistorted, just covers the square viewport with
    /// no gaps -- the same "object-fit: cover" baseline `squareArtwork` computes for real
    /// artwork, and this view's zoom gesture's 1x starting point.
    private var baseFillScale: CGFloat {
        max(viewportSize / imageSize.width, viewportSize / imageSize.height)
    }

    private var effectiveScale: CGFloat { baseFillScale * zoom }

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text("Reposition Cover")
                        .font(.title3.bold())
                    Text("Drag to move, pinch to zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                cropViewport
                    .padding(.top, 4)

                Spacer()

                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        onConfirm(renderCroppedImage())
                    } label: {
                        Text("Use Photo")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.accentGradient))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
        .frame(width: 420, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
    }

    private var cropViewport: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width * effectiveScale, height: imageSize.height * effectiveScale)
                .offset(offset)
        }
        .frame(width: viewportSize, height: viewportSize)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
        )
        .gesture(SimultaneousGesture(dragGesture, magnifyGesture))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(
                    CGSize(width: steadyOffset.width + value.translation.width, height: steadyOffset.height + value.translation.height),
                    scale: effectiveScale
                )
            }
            .onEnded { _ in steadyOffset = offset }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(steadyZoom * value, 1), maxZoom)
                offset = clampedOffset(offset, scale: effectiveScale)
            }
            .onEnded { _ in
                steadyZoom = zoom
                steadyOffset = offset
            }
    }

    /// Keeps the image from being dragged/zoomed so far that a gap opens up inside the
    /// viewport -- clamps to however far the scaled image can move while still fully
    /// covering the square on both axes.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let maxX = max((scaledWidth - viewportSize) / 2, 0)
        let maxY = max((scaledHeight - viewportSize) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    /// Bakes exactly what's visible inside the crop viewport into a new square
    /// `NSImage`, at a fixed output resolution rather than whatever the on-screen
    /// preview happens to be rendered at, so the saved cover stays sharp regardless of
    /// window/display scale.
    private func renderCroppedImage() -> NSImage {
        let outputSize: CGFloat = 600
        let scaledWidth = imageSize.width * effectiveScale
        let scaledHeight = imageSize.height * effectiveScale

        // Where the viewport's square sits within the *scaled* image, in scaled-image
        // points measured from the scaled image's own top-left corner.
        let viewportOriginInScaled = CGPoint(
            x: (scaledWidth - viewportSize) / 2 - offset.width,
            y: (scaledHeight - viewportSize) / 2 - offset.height
        )

        // Convert back to the source image's own point space (undo `effectiveScale`).
        var cropRect = CGRect(
            x: viewportOriginInScaled.x / effectiveScale,
            y: viewportOriginInScaled.y / effectiveScale,
            width: viewportSize / effectiveScale,
            height: viewportSize / effectiveScale
        )
        // Clamp defensively -- the drag/zoom clamping above should already guarantee
        // this stays in-bounds, but a crop rect that steps outside the source image
        // would otherwise draw blank space into the output.
        cropRect.origin.x = min(max(cropRect.origin.x, 0), max(imageSize.width - cropRect.width, 0))
        cropRect.origin.y = min(max(cropRect.origin.y, 0), max(imageSize.height - cropRect.height, 0))

        let output = NSImage(size: NSSize(width: outputSize, height: outputSize))
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        // `NSImage.draw(in:from:...)` measures its `from` rect with the origin at the
        // bottom-left (AppKit's flipped-from-SwiftUI convention), while `cropRect` above
        // was computed top-down to match the on-screen drag/zoom math -- flip the y
        // origin here to convert between the two.
        let flippedFromRect = CGRect(
            x: cropRect.origin.x,
            y: imageSize.height - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )
        image.draw(
            in: NSRect(x: 0, y: 0, width: outputSize, height: outputSize),
            from: flippedFromRect,
            operation: .copy,
            fraction: 1.0
        )
        output.unlockFocus()
        return output
    }
}
