import Foundation

/// Turns the Familiarity dial + five signal weights into an actual song ordering,
/// scored from Sift's own accumulated listening history for each song.
@MainActor
enum SmartControlEngine {
    static func orderedQueue(songs: [SiftSong], settings: SmartControlSettings) -> [SiftSong] {
        let genreFilter = settings.selectedGenres
        let artistFilter = settings.selectedArtists

        let eligible = songs.filter { song in
            (genreFilter.isEmpty || genreFilter.contains(song.genre)) &&
            (artistFilter.isEmpty || artistFilter.contains(song.artist))
        }

        guard !eligible.isEmpty else { return songs.shuffled() }

        let skipWeight = multiplier(for: "Skips in Shuffle", in: settings)
        let recentWeight = multiplier(for: "Recently Played", in: settings)
        let repeatWeight = multiplier(for: "On Repeat", in: settings)
        let minutesWeight = multiplier(for: "Minutes Listened", in: settings)
        let history = ListeningHistoryStore.shared
        let dialFavorsMostPlayed = settings.familiarity >= 0.5

        func familiarityScore(_ song: SiftSong) -> Double {
            let entry = history.entry(for: song.libraryID)
            let daysSinceLastPlay = entry.lastPlayedAt.map { Date().timeIntervalSince($0) / 86_400 } ?? 90

            var score = 0.0
            score += Double(entry.plays) * 3.0
            score += (entry.totalSecondsListened / 60) * minutesWeight * 0.2
            score -= min(daysSinceLastPlay, 90) * recentWeight * 0.3
            score += Double(entry.repeatsInSession) * repeatWeight * 2.0
            score -= Double(entry.skips) * skipWeight * 4.0
            return score
        }

        // Shuffle first so brand-new songs (identical, all-zero history) don't sort
        // into the same order every time — only songs with real signal separate out.
        var ordered = eligible.shuffled()
        ordered.sort { a, b in
            let scoreA = familiarityScore(a)
            let scoreB = familiarityScore(b)
            guard scoreA != scoreB else { return false }
            return dialFavorsMostPlayed ? scoreA > scoreB : scoreA < scoreB
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
