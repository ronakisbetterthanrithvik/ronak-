import MusicKit
import Foundation
import Combine

enum PlaybackError: LocalizedError {
    case noPlayableSongs

    var errorDescription: String? {
        switch self {
        case .noPlayableSongs:
            return "None of these songs are available to stream through Apple Music right now."
        }
    }
}

/// Wraps `ApplicationMusicPlayer` and feeds every play/skip back into
/// `ListeningHistoryStore`, which is the first-party signal `SmartControlEngine` scores on.
@MainActor
final class PlaybackService: ObservableObject {
    static let shared = PlaybackService()

    private let player = ApplicationMusicPlayer.shared
    private let history = ListeningHistoryStore.shared

    /// A skip counts as leaving a track before this many seconds of listening.
    private let skipThreshold: TimeInterval = 20

    /// A full playlist (Sift has seen library playlists well over 1,000 songs) is too
    /// much to hand `ApplicationMusicPlayer.Queue` at once — building that many entries
    /// is slow and, combined with any songs missing play parameters (not catalog-matched,
    /// see `MusicLibraryService`), can stall playback with nothing audible. Queue a
    /// reasonable batch instead, like a real player would.
    private let maxQueueSize = 50

    @Published var isPlaying = false

    /// The library ID of whatever's currently loaded in the player, so the UI can show
    /// a "Now Playing" indicator and highlight the matching row in the track list. Stays
    /// set while paused — it only clears once nothing is loaded at all.
    @Published private(set) var nowPlayingLibraryID: String?

    private var trackStartedAt: Date?

    func playInOrder(_ songs: [SiftSong]) async throws {
        try await start(with: songs)
    }

    func shufflePlay(_ songs: [SiftSong], settings: SmartControlSettings) async throws {
        let ordered = SmartControlEngine.orderedQueue(songs: songs, settings: settings)
        try await start(with: ordered)
    }

    /// Plays a specific tapped song, then continues through the rest of `songs` in order
    /// starting from that point — same as tapping a track in a normal music app.
    func play(_ song: SiftSong, from songs: [SiftSong]) async throws {
        guard let startIndex = songs.firstIndex(where: { $0.libraryID == song.libraryID }) else {
            try await start(with: songs)
            return
        }
        try await start(with: Array(songs[startIndex...]))
    }

    func skipToNext() async {
        finishTrackingCurrentTrack()
        do {
            try await player.skipToNextEntry()
            beginTrackingCurrentEntry(knownLibraryID: resolveCurrentLibraryID())
        } catch {
            print("Sift: skip failed — \(error)")
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        finishTrackingCurrentTrack()
    }

    private func start(with songs: [SiftSong]) async throws {
        // Some library songs aren't matched to Apple's streaming catalog and can't be
        // queued at all (that's what "missing play parameters" means at runtime) --
        // filter those out ourselves instead of letting them choke queue construction.
        let musicKitSongs = Array(
            songs
                .compactMap { MusicLibraryService.shared.song(for: $0.libraryID) }
                .filter { $0.playParameters != nil }
                .prefix(maxQueueSize)
        )
        guard !musicKitSongs.isEmpty else { throw PlaybackError.noPlayableSongs }

        player.queue = ApplicationMusicPlayer.Queue(for: musicKitSongs)
        try await player.play()
        isPlaying = true
        // `player.queue.currentEntry` isn't reliably populated the instant play() returns,
        // so use the song we know we just told it to start with instead of querying it back.
        beginTrackingCurrentEntry(knownLibraryID: musicKitSongs[0].id.rawValue)
    }

    private func resolveCurrentLibraryID() -> String? {
        guard let item = player.queue.currentEntry?.item else { return nil }
        if case let .song(song) = item {
            return song.id.rawValue
        }
        return nil
    }

    private func beginTrackingCurrentEntry(knownLibraryID: String?) {
        nowPlayingLibraryID = knownLibraryID
        trackStartedAt = Date()
    }

    private func finishTrackingCurrentTrack() {
        guard let libraryID = nowPlayingLibraryID, let startedAt = trackStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < skipThreshold {
            history.recordSkip(libraryID: libraryID)
        } else {
            history.recordPlay(libraryID: libraryID, seconds: elapsed)
        }
        trackStartedAt = nil
    }
}
