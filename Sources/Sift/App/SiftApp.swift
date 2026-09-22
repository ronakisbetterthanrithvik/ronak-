import SwiftUI

@main
struct SiftApp: App {
    var body: some Scene {
        WindowGroup {
            PlaylistDetailView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1040, height: 720)
    }
}
