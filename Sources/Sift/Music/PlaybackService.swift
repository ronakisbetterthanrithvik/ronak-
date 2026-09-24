import MusicKit
import Foundation
import Combine

enum PlaybackError: LocalizedError {
    case noPlayableSongs

    var errorDescription: String? {
        switch self {
        case .noPlayableSongs:
            return "This song isn't available to stream through Apple Music right now."
        }
    }
}

/// Wraps `ApplicationMusicPlayer` and feeds every play/skip back into
/// `ListeningHistoryStore`, which is the first-party signal `SmartControlEngine` scores on.
@MainActor
final class PlaybackService: ObservableObject {
    static let shared = PlaybackService()

    private let player = ApplicationMusicPlayer.shared
    private let listeningHistory = ListeningHistoryStore.shared

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

    /// The current song plus everything queued after it, in order — `queuedSongs.first`
    /// is always what's playing now. Kept in step with the real MusicKit queue by every
    /// method below, so the UI never has to query MusicKit's queue directly.
    @Published private(set) var queuedSongs: [SiftSong] = []

    /// Songs skipped past, most recent last, so `skipToPrevious()` has something to go back to.
    private var playedHistory: [SiftSong] = []

    private var trackStartedAt: Date?

    /// Elapsed time into whatever's currently loaded, straight from the player. MusicKit
    /// doesn't publish this as a Combine value, so the now-playing progress bar polls it
    /// directly (via a `TimelineView`) instead of Sift maintaining its own timer.
    var currentPlaybackTime: TimeInterval { player.playbackTime }

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
        guard queuedSongs.count > 1 else { return }
        finishTrackingCurrentTrack()
        do {
            try await player.skipToNextEntry()
            playedHistory.append(queuedSongs.removeFirst())
            beginTrackingCurrentEntry(knownLibraryID: queuedSongs.first?.libraryID)
        } catch {
            print("Sift: skip failed — \(error)")
        }
    }

    func skipToPrevious() async {
        guard let previous = playedHistory.last else { return }
        finishTrackingCurrentTrack()
        do {
            try await player.skipToPreviousEntry()
            playedHistory.removeLast()
            queuedSongs.insert(previous, at: 0)
            beginTrackingCurrentEntry(knownLibraryID: previous.libraryID)
        } catch {
            print("Sift: skip back failed — \(error)")
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        finishTrackingCurrentTrack()
    }

    /// Resumes whatever's already loaded (from `pause()`), rather than rebuilding the
    /// queue and starting over — used when tapping the currently-playing row again.
    func resume() async throws {
        try await player.play()
        isPlaying = true
        trackStartedAt = Date()
    }

    /// Removes a song further down the queue (never the currently playing one, at index
    /// 0 — skip past it instead). Mirrors the removal into MusicKit's real queue.
    ///
    /// - Note: relies on `player.queue.entries` supporting direct removal. If this
    ///   doesn't compile against your SDK, Xcode's autocomplete on `player.queue.entries.`
    ///   will show the current mutation API — the intent (drop that one upcoming song)
    ///   stays the same.
    func removeFromQueue(at index: Int) {
        guard queuedSongs.indices.contains(index), index != 0 else { return }
        let removed = queuedSongs[index]
        queuedSongs.remove(at: index)

        if let entryIndex = player.queue.entries.firstIndex(where: { entry in
            guard case let .song(song) = entry.item else { return false }
            return song.id.rawValue == removed.libraryID
        }) {
            player.queue.entries.remove(at: entryIndex)
        }
    }

    /// Reorders the "up next" portion of the queue (offsets exclude the currently
    /// playing song at `queuedSongs[0]`) to match a drag-to-reorder gesture in the UI,
    /// and mirrors the same move into MusicKit's real queue so what plays next actually
    /// matches what's shown.
    ///
    /// - Note: relies on `player.queue.entries` supporting `remove(at:)`/`insert(_:at:)`,
    ///   the same assumption `removeFromQueue` already makes — if this doesn't compile
    ///   against your SDK, Xcode's autocomplete on `player.queue.entries.` will show the
    ///   current mutation API.
    func moveQueuedSongs(fromUpNextOffsets source: IndexSet, toUpNextOffset destination: Int) {
        guard queuedSongs.count > 1, let sourceOffset = source.first, source.count == 1 else { return }

        var upNext = Array(queuedSongs.dropFirst())
        guard upNext.indices.contains(sourceOffset) else { return }
        let moved = upNext.remove(at: sourceOffset)
        // `destination` follows SwiftUI's onMove convention: it's the target index as if
        // the removal already happened, so shift it back by one when the item moved to a
        // later position in the (now one-shorter) array.
        let insertOffset = sourceOffset < destination ? destination - 1 : destination
        upNext.insert(moved, at: min(max(insertOffset, 0), upNext.count))
        queuedSongs = [queuedSongs[0]] + upNext

        guard let entryIndex = player.queue.entries.firstIndex(where: { entry in
            guard case let .song(song) = entry.item else { return false }
            return song.id.rawValue == moved.libraryID
        }) else { return }
        let entry = player.queue.entries.remove(at: entryIndex)
        let newUpNextIndex = upNext.firstIndex(where: { $0.libraryID == moved.libraryID }) ?? upNext.count
        let insertionIndex = min(newUpNextIndex + 1, player.queue.entries.count)
        player.queue.entries.insert(entry, at: insertionIndex)
    }

    /// Adds a song to the queue without interrupting what's currently playing — either
    /// right after the current song (`playNext: true`) or at the very end.
    ///
    /// - Note: `Queue.insert(_:position:)` is my best recollection of this MusicKit API;
    ///   if the signature differs in your SDK, autocomplete on `player.queue.` will show
    ///   the current form.
    func enqueue(_ song: SiftSong, playNext: Bool) async throws {
        guard let mkSong = MusicLibraryService.shared.song(for: song.libraryID), mkSong.playParameters != nil else {
            throw PlaybackError.noPlayableSongs
        }

        guard !queuedSongs.isEmpty else {
            try await start(with: [song])
            return
        }

        try await player.queue.insert(mkSong, position: playNext ? .afterCurrentEntry : .tail)
        if playNext {
            queuedSongs.insert(song, at: min(1, queuedSongs.count))
        } else {
            queuedSongs.append(song)
        }
    }

    private func start(with songs: [SiftSong]) async throws {
        // Some library songs aren't matched to Apple's streaming catalog and can't be
        // queued at all (that's what "missing play parameters" means at runtime) --
        // filter those out ourselves instead of letting them choke queue construction.
        let playable = Array(
            songs.filter { song in
                MusicLibraryService.shared.song(for: song.libraryID)?.playParameters != nil
            }
            .prefix(maxQueueSize)
        )
        let musicKitSongs = playable.compactMap { MusicLibraryService.shared.song(for: $0.libraryID) }
        guard !musicKitSongs.isEmpty else { throw PlaybackError.noPlayableSongs }

        player.queue = ApplicationMusicPlayer.Queue(for: musicKitSongs)
        try await player.play()
        isPlaying = true
        queuedSongs = playable
        playedHistory = []
        // `player.queue.currentEntry` isn't reliably populated the instant play() returns,
        // so use the song we know we just told it to start with instead of querying it back.
        beginTrackingCurrentEntry(knownLibraryID: playable[0].libraryID)
    }

    private func beginTrackingCurrentEntry(knownLibraryID: String?) {
        nowPlayingLibraryID = knownLibraryID
        trackStartedAt = Date()
    }

    private func finishTrackingCurrentTrack() {
        guard let libraryID = nowPlayingLibraryID, let startedAt = trackStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < skipThreshold {
            listeningHistory.recordSkip(libraryID: libraryID)
        } else {
            listeningHistory.recordPlay(libraryID: libraryID, seconds: elapsed)
        }
        trackStartedAt = nil
    }
}
