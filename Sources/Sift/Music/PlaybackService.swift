import MusicKit
import Foundation

/// Wraps `ApplicationMusicPlayer` and feeds every play/skip back into
/// `ListeningHistoryStore`, which is the first-party signal `SmartControlEngine` scores on.
@MainActor
final class PlaybackService: ObservableObject {
    static let shared = PlaybackService()

    private let player = ApplicationMusicPlayer.shared
    private let history = ListeningHistoryStore.shared

    /// A skip counts as leaving a track before this many seconds of listening.
    private let skipThreshold: TimeInterval = 20

    @Published var isPlaying = false

    private var trackedLibraryID: String?
    private var trackStartedAt: Date?

    func playInOrder(_ songs: [SiftSong]) async {
        await start(with: songs)
    }

    func shufflePlay(_ songs: [SiftSong], settings: SmartControlSettings) async {
        let ordered = SmartControlEngine.orderedQueue(songs: songs, settings: settings)
        await start(with: ordered)
    }

    func skipToNext() async {
        finishTrackingCurrentTrack()
        do {
            try await player.skipToNextEntry()
            beginTrackingCurrentEntry()
        } catch {
            print("Sift: skip failed — \(error)")
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        finishTrackingCurrentTrack()
    }

    private func start(with songs: [SiftSong]) async {
        let musicKitSongs = songs.compactMap { MusicLibraryService.shared.song(for: $0.libraryID) }
        guard !musicKitSongs.isEmpty else { return }

        do {
            player.queue = ApplicationMusicPlayer.Queue(for: musicKitSongs)
            try await player.play()
            isPlaying = true
            beginTrackingCurrentEntry()
        } catch {
            print("Sift: playback failed — \(error)")
        }
    }

    private func currentLibraryID() -> String? {
        guard let item = player.queue.currentEntry?.item, case let song as Song = item else {
            return nil
        }
        return song.id.rawValue
    }

    private func beginTrackingCurrentEntry() {
        trackedLibraryID = currentLibraryID()
        trackStartedAt = Date()
    }

    private func finishTrackingCurrentTrack() {
        guard let libraryID = trackedLibraryID, let startedAt = trackStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < skipThreshold {
            history.recordSkip(libraryID: libraryID)
        } else {
            history.recordPlay(libraryID: libraryID, seconds: elapsed)
        }
        trackedLibraryID = nil
        trackStartedAt = nil
    }
}
