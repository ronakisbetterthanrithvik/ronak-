import SwiftUI

@main
struct SiftApp: App {
    init() {
        #if DEBUG
        // Every Xcode Run starts back at MusicServiceChooserView instead of remembering
        // a previous choice, so the chooser/Spotify screens stay easy to check while
        // they're being built. Only compiled into Debug builds -- a real release build
        // (Archive/TestFlight/App Store) keeps the saved choice as normal.
        UserDefaults.standard.removeObject(forKey: "sift.selectedMusicService")
        #endif
    }

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
