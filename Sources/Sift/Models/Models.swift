import Foundation
import SwiftUI
import MusicKit
import AppKit

struct SiftSong: Identifiable, Hashable {
    let id = UUID()
    /// Stable across app launches: MusicKit's own `Song.id.rawValue` for library songs,
    /// or a deterministic placeholder for demo data. Used as the listening-history key.
    let libraryID: String
    let title: String
    let artist: String
    let album: String
    let genre: String
    let duration: TimeInterval
    /// The song's own artwork. Nil for demo data. Kept as MusicKit's own `Artwork` (not a
    /// resolved URL) and rendered with MusicKit's `ArtworkImage` view -- a plain
    /// `AsyncImage(url:)` can't load it, since library-only artwork resolves to a
    /// `musicKit://artwork/transient/...` reference rather than a real downloadable URL.
    var artwork: Artwork? = nil
}

extension SiftSong {
    /// This song's title with any trailing "(feat. ...)" / "[feat. ...]" credit removed --
    /// Apple Music's own metadata folds featured artists into the title string itself, but
    /// visually that credit belongs alongside the artist name underneath (see
    /// `displayArtist`), not competing with the song name on its own line.
    var displayTitle: String {
        title.splittingFeaturedCredit().title
    }

    /// "A$AP Mob" becomes "A$AP Mob (feat. A$AP Rocky, ...)" when the title carried a
    /// featured-artist credit -- see `displayTitle`.
    var displayArtist: String {
        guard let credit = title.splittingFeaturedCredit().featuredCredit else { return artist }
        return "\(artist) \(credit)"
    }
}

private extension String {
    /// Splits a trailing featured-artist credit -- "(feat. X, Y)", "[ft. X]",
    /// "(featuring X)", any capitalization -- off a song title. Returns the title
    /// unchanged with a nil credit if it has none.
    func splittingFeaturedCredit() -> (title: String, featuredCredit: String?) {
        let pattern = #"[\(\[](feat\.?|ft\.?|featuring)\s+(.+?)[\)\]]\s*$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
            let namesRange = Range(match.range(at: 2), in: self),
            let wholeRange = Range(match.range, in: self)
        else {
            return (self, nil)
        }
        let strippedTitle = String(self[..<wholeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (strippedTitle, "(feat. \(self[namesRange]))")
    }
}

struct SiftPlaylist {
    /// MusicKit's own `Playlist.id.rawValue` once connected to a real library playlist, nil for demo data.
    var libraryID: String?
    let name: String
    let ownerName: String
    let songCount: Int
    let totalDuration: TimeInterval
    let songs: [SiftSong]
    let genresPresent: [String]
    let topArtists: [String]
    let allArtists: [String]
    /// The playlist's real cover art. Nil for demo data, or for personal playlists without
    /// a custom cover set (which is most of them) -- for those, use the first few
    /// `mosaicArtwork` instead, matching how Apple Music itself covers them. See
    /// `SiftSong.artwork` for why this stays a MusicKit `Artwork` rather than a `URL`.
    var artwork: Artwork? = nil
    var mosaicArtwork: [Artwork] = []
    /// A cover picked locally for a Sift-only playlist (see `SiftOwnedPlaylist`), which
    /// has no MusicKit `Artwork` of its own to fall back on. Checked before `artwork`/
    /// `mosaicArtwork` wherever this playlist's cover is displayed.
    var localArtworkImage: NSImage? = nil
}

enum Weight: String, CaseIterable, Identifiable, Hashable {
    case low = "Low"
    case medium = "Med"
    case high = "High"

    var id: String { rawValue }
}

struct SignalControl: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    var weight: Weight
}

enum AutoSortMode: String, CaseIterable, Identifiable, Hashable {
    case genre = "Genre"
    case vibe = "Vibe"
    case artist = "Artist"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .genre:
            return "Grouped by the genre metadata already on these songs. Most predictable, least novel."
        case .vibe:
            return "Grouped by mood and energy — tempo, energy, and how you listen. Still in beta while we tune it."
        case .artist:
            return "Grouped by the artists you have the most songs from in this playlist."
        }
    }
}

struct ProposedPlaylist: Identifiable {
    let id = UUID()
    let name: String
    let songCount: Int
    let duration: TimeInterval
    let previewTracks: [String]
    let gradient: [Color]
    /// Library IDs of the songs behind this proposal, used to actually create the
    /// playlist in Apple Music. Empty for demo data.
    var songLibraryIDs: [String] = []
    var isSelected: Bool = true
}

struct SmartControlSettings {
    var familiarity: Double
    var signals: [SignalControl]
    var selectedGenres: Set<String>
    var selectedArtists: Set<String>

    static func `default`(for playlist: SiftPlaylist) -> SmartControlSettings {
        SmartControlSettings(
            familiarity: 0.28,
            signals: [
                SignalControl(icon: "shuffle", title: "Skips in Shuffle", subtitle: "Songs you skip drop lower in the queue", weight: .high),
                SignalControl(icon: "clock.arrow.circlepath", title: "Recently Played", subtitle: "How recently a song was in rotation", weight: .medium),
                SignalControl(icon: "repeat", title: "On Repeat", subtitle: "Songs you replay back-to-back climb higher", weight: .medium),
                SignalControl(icon: "waveform", title: "Minutes Listened", subtitle: "Total listening time per song, all-time", weight: .low),
                SignalControl(icon: "square.grid.2x2", title: "Genre Balance", subtitle: "Keep a mix across the genres selected below", weight: .high)
            ],
            selectedGenres: [],
            selectedArtists: []
        )
    }

    /// `hasHistory` should be true only once Sift has recorded a real play or skip for at
    /// least one song here — otherwise every song scores identically (see
    /// `SmartControlEngine`) and this dial has no actual effect on Shuffle yet, so the
    /// caption says that plainly instead of claiming a bias that isn't there.
    func familiarityCaption(hasHistory: Bool) -> String {
        guard hasHistory else {
            return "Still learning — Sift hasn't seen enough plays or skips here yet, so Shuffle is just random for now. This starts reflecting real habits once you've used Play/Shuffle in Sift a bit."
        }
        switch familiarity {
        case ..<0.35:
            return "Currently favoring the deep cuts you almost never hit play on."
        case 0.35..<0.65:
            return "Balanced between deep cuts and the songs you already know."
        default:
            return "Currently favoring the songs you already play the most."
        }
    }

    mutating func applyFamiliarityPreset(for newValue: Double) {
        familiarity = newValue

        func index(of title: String) -> Int? {
            signals.firstIndex { $0.title == title }
        }

        let biasedWeight: Weight
        if newValue < 0.35 {
            biasedWeight = .low
        } else if newValue > 0.65 {
            biasedWeight = .high
        } else {
            biasedWeight = .medium
        }

        for title in ["Recently Played", "On Repeat", "Minutes Listened"] {
            if let i = index(of: title) {
                signals[i].weight = biasedWeight
            }
        }
    }
}
