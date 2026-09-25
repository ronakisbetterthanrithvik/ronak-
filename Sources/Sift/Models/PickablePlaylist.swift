import Foundation

/// Either a real Apple Music library playlist or one of Sift's own local-only
/// playlists (see `SiftOwnedPlaylist`) -- the "Choose a Playlist" carousel shows both
/// side by side, since a playlist Auto-Sort creates should be just as reachable as one
/// from your real library.
enum PickablePlaylist: Identifiable, Hashable {
    case library(LibraryPlaylistSummary)
    case sift(SiftOwnedPlaylist)

    var id: String {
        switch self {
        case .library(let summary): return summary.id
        case .sift(let playlist): return playlist.id.uuidString
        }
    }

    var name: String {
        switch self {
        case .library(let summary): return summary.name
        case .sift(let playlist): return playlist.name
        }
    }
}
