import Foundation
import SwiftUI

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
