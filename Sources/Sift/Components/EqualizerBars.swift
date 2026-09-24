import SwiftUI

/// A small "now playing" indicator that animates continuously while `isPlaying` is true.
///
/// MusicKit doesn't expose raw audio/amplitude data for DRM-streamed playback, so a
/// third-party app can't do true audio-reactive analysis here -- this uses the same kind
/// of stylized looping animation real music apps use for this exact indicator (Apple
/// Music's own sidebar equalizer icon works the same way, not from real audio analysis).
struct EqualizerBars: View {
    var isPlaying: Bool
    var color: Color = Theme.accentSecondary

    @State private var heights: [CGFloat] = [0.4, 0.9, 0.6]

    private let barCount = 3
    private let barHeight: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: barHeight * heights[index])
            }
        }
        .frame(width: 16, height: barHeight, alignment: .bottom)
        .onAppear { animateAllBars() }
        .onChange(of: isPlaying) { _, playing in
            if playing { animateAllBars() }
        }
    }

    private func animateAllBars() {
        for index in 0..<barCount {
            animateBar(index)
        }
    }

    private func animateBar(_ index: Int) {
        guard isPlaying else { return }
        let duration = Double.random(in: 0.35...0.6)
        withAnimation(.easeInOut(duration: duration)) {
            heights[index] = CGFloat.random(in: 0.25...1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            animateBar(index)
        }
    }
}
