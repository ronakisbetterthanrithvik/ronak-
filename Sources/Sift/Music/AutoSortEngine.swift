import SwiftUI

/// Computes real Genre/Artist Auto-Sort proposals from a loaded playlist's songs. Vibe
/// proposals are built the same visual way (see `vibeProposal`) but the actual song
/// selection for those comes from `ClaudeVibeService` instead, since matching a
/// free-text request like "hype songs" needs real language understanding that MusicKit's
/// metadata alone can't provide.
@MainActor
enum AutoSortEngine {
    static func genreGroups(from songs: [SiftSong]) -> [ProposedPlaylist] {
        let result = groups(from: songs, keysFor: { [$0.genre] }, minimumSongs: 1, defaultSelected: true)
        // Some library songs -- confirmed via debug logging in `MusicLibraryService`,
        // consistent across both a playlist's own `.tracks` fetch and a direct by-id
        // library fetch -- come back from MusicKit with no genre metadata at all. That's
        // a real Apple Music/MusicKit limitation for those songs (often ones matched
        // into iCloud Music Library rather than purchased), not something this app can
        // force to appear. When every single song in the playlist is affected, a lone
        // "Unknown" bucket covering all of them isn't a real grouping -- show nothing
        // instead of a group that just looks broken.
        if result.count == 1, result[0].name == "Unknown" {
            return []
        }
        return result
    }

    static func artistGroups(from songs: [SiftSong], minimumSongs: Int = 3) -> [ProposedPlaylist] {
        // A song credited to multiple artists ("Playboi Carti & Travis Scott") belongs
        // under each artist's own group, not lumped into a one-off combined-name group.
        // A big library can produce dozens of artist groups (every artist with 3+ songs),
        // so these start unselected -- picking every one by default would silently queue
        // up creating dozens of playlists at once.
        groups(from: songs, keysFor: { $0.artist.splitArtistCredits() }, minimumSongs: minimumSongs, defaultSelected: false)
    }

    /// Builds a proposal from a curated song selection -- the same preview-track/gradient
    /// treatment as the Genre and Artist proposals above. Used by Auto-Sort's Vibe tab
    /// (`ClaudeVibeService`'s curated subset of the current playlist) and by the AI
    /// Playlist Generator (`CatalogPlaylistGeneratorService`'s catalog-wide result) alike.
    static func vibeProposal(name: String, songs: [SiftSong]) -> ProposedPlaylist {
        ProposedPlaylist(
            name: name,
            songCount: songs.count,
            duration: songs.reduce(0) { $0 + $1.duration },
            previewTracks: Array(songs.prefix(3).map(\.title)),
            gradient: gradient(seededBy: name),
            songLibraryIDs: songs.map(\.libraryID)
        )
    }

    private static func groups(
        from songs: [SiftSong],
        keysFor: (SiftSong) -> [String],
        minimumSongs: Int,
        defaultSelected: Bool
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
                    songLibraryIDs: songsInGroup.map(\.libraryID),
                    isSelected: defaultSelected
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
