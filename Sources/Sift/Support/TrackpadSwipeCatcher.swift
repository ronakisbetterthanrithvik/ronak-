import AppKit
import SwiftUI

/// Bridges raw two-finger trackpad horizontal scroll into SwiftUI -- there's no native
/// SwiftUI modifier for this on macOS, so this wraps a plain NSView that overrides
/// `scrollWheel(with:)` directly. Lets the carousel page with a sideways trackpad swipe,
/// the same way the arrow buttons already do, without needing an actual `ScrollView`
/// (which would fight with the carousel's own absolute tile positioning).
struct TrackpadSwipeCatcher: NSViewRepresentable {
    var onSwipeForward: () -> Void
    var onSwipeBackward: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSwipeForward = onSwipeForward
        view.onSwipeBackward = onSwipeBackward
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onSwipeForward = onSwipeForward
        nsView.onSwipeBackward = onSwipeBackward
    }

    final class CatcherView: NSView {
        var onSwipeForward: (() -> Void)?
        var onSwipeBackward: (() -> Void)?

        private var accumulatedDeltaX: CGFloat = 0
        private var hasFiredThisGesture = false
        private let triggerThreshold: CGFloat = 80

        /// Claims only scroll-wheel events -- every other event type (a click, the
        /// reorder drag) returns `nil` here so it passes straight through to whatever
        /// SwiftUI content (tiles, buttons) sits in the same screen region, instead of
        /// this view swallowing taps meant for them. `hitTest` itself only ever gets a
        /// point, not an event, so checking the app's *current* event's type inside it is
        /// the standard way to make that per-event-type split possible at all.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? self : nil
        }

        override func scrollWheel(with event: NSEvent) {
            switch event.phase {
            case .began:
                accumulatedDeltaX = 0
                hasFiredThisGesture = false
            case .changed:
                guard !hasFiredThisGesture else { return }
                accumulatedDeltaX += event.scrollingDeltaX
                // Sign convention here is my best understanding of how macOS reports a
                // natural-scrolling two-finger swipe, not something testable from this
                // environment -- if forward/backward come out swapped once run for real,
                // swap these two branches' callbacks.
                if accumulatedDeltaX <= -triggerThreshold {
                    hasFiredThisGesture = true
                    onSwipeForward?()
                } else if accumulatedDeltaX >= triggerThreshold {
                    hasFiredThisGesture = true
                    onSwipeBackward?()
                }
            default:
                break
            }
        }
    }
}
