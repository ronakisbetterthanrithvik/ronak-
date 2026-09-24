import SwiftUI

/// Computes real Genre/Artist Auto-Sort proposals from a loaded playlist's songs.
///
/// Vibe mode needs Sift's own mood/energy classifier — MusicKit's public API doesn't
/// expose tempo/energy/valence — so per the PRD it stays out of this v1 engine and the
/// Vibe tab in the UI is labeled Beta rather than backed by real grouping here.
@MainActor
enum AutoSortEngine {
    static func genreGroups(from songs: [SiftSong]) -> [ProposedPlaylist] {
        groups(from: songs, keysFor: { [$0.genre] }, minimumSongs: 1)
    }

    static func artistGroups(from songs: [SiftSong], minimumSongs: Int = 3) -> [ProposedPlaylist] {
        // A song credited to multiple artists ("Playboi Carti & Travis Scott") belongs
        // under each artist's own group, not lumped into a one-off combined-name group.
        groups(from: songs, keysFor: { $0.artist.splitArtistCredits() }, minimumSongs: minimumSongs)
    }

    private static func groups(
        from songs: [SiftSong],
        keysFor: (SiftSong) -> [String],
        minimumSongs: Int
    ) -> [ProposedPlaylist] {
        var grouped: [String: [SiftSong]] = [:]
        for song in songs {
            for key in keysFor(song) {
                grouped[key, default: []].append(song)
            }
        }

        return grouped
            .filter { $0.value.count >= minimumSongs }
            .map { name, songsInGroup in
                ProposedPlaylist(
                    name: name,
                    songCount: songsInGroup.count,
                    duration: songsInGroup.reduce(0) { $0 + $1.duration },
                    previewTracks: Array(songsInGroup.prefix(3).map(\.title)),
                    gradient: gradient(seededBy: name),
                    songLibraryIDs: songsInGroup.map(\.libraryID)
                )
            }
            .sorted { $0.songCount > $1.songCount }
    }

    private static func gradient(seededBy name: String) -> [Color] {
        var hasher = Hasher()
        hasher.combine(name)
        let hash = abs(hasher.finalize())
        let hue1 = Double(hash % 360) / 360
        let hue2 = Double((hash / 360) % 360) / 360
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.85),
            Color(hue: hue2, saturation: 0.55, brightness: 0.55)
        ]
    }
}
