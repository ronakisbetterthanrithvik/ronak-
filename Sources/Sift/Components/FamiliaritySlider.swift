import SwiftUI

struct FamiliaritySlider: View {
    @Binding var value: Double
    var onCommit: (Double) -> Void = { _ in }

    private let knobSize: CGFloat = 20
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - knobSize, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.prismGradient)
                    .frame(height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .offset(x: value * usableWidth)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clamped = min(max(0, drag.location.x), usableWidth)
                        value = usableWidth > 0 ? clamped / usableWidth : 0
                    }
                    .onEnded { _ in onCommit(value) }
            )
        }
        .frame(height: knobSize)
    }
}
