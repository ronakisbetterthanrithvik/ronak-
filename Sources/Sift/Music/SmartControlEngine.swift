import Foundation

/// Turns the Familiarity dial + five signal weights into an actual song ordering,
/// scored from Sift's own accumulated listening history for each song.
@MainActor
enum SmartControlEngine {
    static func orderedQueue(songs: [SiftSong], settings: SmartControlSettings) -> [SiftSong] {
        let genreFilter = settings.selectedGenres
        let artistFilter = settings.selectedArtists

        let eligible = songs.filter { song in
            // A song credited to multiple artists ("Playboi Carti & Travis Scott") should
            // match a filter on any one of its credited artists, not just the full string.
            let songArtists = Set(song.artist.splitArtistCredits())
            return (genreFilter.isEmpty || genreFilter.contains(song.genre)) &&
                (artistFilter.isEmpty || !artistFilter.isDisjoint(with: songArtists))
        }

        guard !eligible.isEmpty else { return songs.shuffled() }

        // Genre/artist filtering still applies either way -- this only skips the
        // listening-history-weighted ordering itself, for a plain random shuffle instead.
        guard settings.isSmartShuffleEnabled else { return eligible.shuffled() }

        let skipWeight = multiplier(for: "Skips in Shuffle", in: settings)
        let recentWeight = multiplier(for: "Recently Played", in: settings)
        let repeatWeight = multiplier(for: "On Repeat", in: settings)
        let minutesWeight = multiplier(for: "Minutes Listened", in: settings)
        let history = ListeningHistoryStore.shared
        let dialFavorsMostPlayed = settings.familiarity >= 0.5

        // Split into two pieces instead of one combined score -- `preference` legitimately
        // flips meaning with the dial (more plays should sort first when favoring
        // most-played, last when favoring deep cuts), but `skipPenalty` must not: a
        // heavily-skipped song should always rank later, never earlier, regardless of
        // which way the dial points. Folding both into one score and reversing the whole
        // thing for "favor deep cuts" used to flip the skip penalty's sign along with it,
        // so a song skipped a lot got read as an overlooked deep cut and sorted first --
        // the opposite of "Skips in Shuffle: songs you skip drop lower in the queue."
        func rankValue(_ song: SiftSong) -> Double {
            let entry = history.entry(for: song.libraryID)
            let daysSinceLastPlay = entry.lastPlayedAt.map { Date().timeIntervalSince($0) / 86_400 } ?? 90

            var preference = 0.0
            preference += Double(entry.plays) * 3.0
            preference += (entry.totalSecondsListened / 60) * minutesWeight * 0.2
            preference -= min(daysSinceLastPlay, 90) * recentWeight * 0.3
            preference += Double(entry.repeatsInSession) * repeatWeight * 2.0

            let skipPenalty = Double(entry.skips) * skipWeight * 4.0
            let flippedPreference = dialFavorsMostPlayed ? -preference : preference
            return flippedPreference + skipPenalty
        }

        // Shuffle first so brand-new songs (identical, all-zero history) don't sort
        // into the same order every time — only songs with real signal separate out.
        var ordered = eligible.shuffled()
        ordered.sort { a, b in
            let rankA = rankValue(a)
            let rankB = rankValue(b)
            guard rankA != rankB else { return false }
            return rankA < rankB
        }
        return ordered
    }

    private static func multiplier(for signalTitle: String, in settings: SmartControlSettings) -> Double {
        switch settings.signals.first(where: { $0.title == signalTitle })?.weight ?? .medium {
        case .low: return 0.4
        case .medium: return 1.0
        case .high: return 2.0
        }
    }
}
