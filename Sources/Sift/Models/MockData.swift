import SwiftUI

extension Playlist {
    static let everything = Playlist(
        name: "My Everything Playlist",
        ownerName: "Ronak",
        songCount: 482,
        totalDuration: 29 * 3600 + 40 * 60,
        sampleSongs: [
            Song(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", genre: "R&B", duration: 200),
            Song(title: "Levitating", artist: "Dua Lipa", album: "Future Nostalgia", genre: "Pop", duration: 203),
            Song(title: "Sunroof", artist: "Nicky Youre", album: "Sunroof", genre: "Electronic", duration: 187),
            Song(title: "good 4 u", artist: "Olivia Rodrigo", album: "SOUR", genre: "Pop", duration: 178),
            Song(title: "As It Was", artist: "Harry Styles", album: "Harry's House", genre: "Indie", duration: 167),
            Song(title: "Take Me Home, Country Roads", artist: "John Denver", album: "Poems, Prayers & Promises", genre: "Country", duration: 189),
            Song(title: "No Role Modelz", artist: "J. Cole", album: "2014 Forest Hills Drive", genre: "Hip-Hop", duration: 292),
            Song(title: "Location", artist: "Khalid", album: "American Teen", genre: "R&B", duration: 233),
            Song(title: "Cruel Summer", artist: "Taylor Swift", album: "Lover", genre: "Pop", duration: 178),
            Song(title: "Redbone", artist: "Childish Gambino", album: "Awaken, My Love!", genre: "Rock", duration: 327)
        ],
        genresPresent: ["Hip-Hop", "R&B", "Pop", "Country", "Indie", "Electronic", "Latin", "Rock", "Jazz"],
        topArtists: ["The Weeknd", "Dua Lipa", "Taylor Swift", "J. Cole"],
        allArtists: ["The Weeknd", "Dua Lipa", "Taylor Swift", "J. Cole", "Olivia Rodrigo", "Harry Styles", "Khalid", "Childish Gambino", "John Denver", "Nicky Youre"]
    )
}

enum AutoSortStore {
    static var proposals: [AutoSortMode: [ProposedPlaylist]] = [
        .genre: [
            ProposedPlaylist(
                name: "Hip-Hop & R&B", songCount: 132, duration: 8 * 3600 + 9 * 60,
                previewTracks: ["No Role Modelz", "Location", "Redbone"],
                gradient: [Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 0.95, green: 0.55, blue: 0.25)]
            ),
            ProposedPlaylist(
                name: "Pop Favorites", songCount: 98, duration: 5 * 3600 + 58 * 60,
                previewTracks: ["Levitating", "good 4 u", "As It Was"],
                gradient: [Color(red: 0.95, green: 0.4, blue: 0.65), Color(red: 0.55, green: 0.35, blue: 0.95)]
            ),
            ProposedPlaylist(
                name: "Country Roads", songCount: 41, duration: 2 * 3600 + 31 * 60,
                previewTracks: ["Take Me Home, Country Roads"],
                gradient: [Color(red: 0.75, green: 0.55, blue: 0.25), Color(red: 0.4, green: 0.6, blue: 0.3)]
            ),
            ProposedPlaylist(
                name: "Indie & Alternative", songCount: 76, duration: 4 * 3600 + 42 * 60,
                previewTracks: ["Snooze", "Cruel Summer"],
                gradient: [Color(red: 0.3, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.6, blue: 0.75)]
            ),
            ProposedPlaylist(
                name: "Electronic & Dance", songCount: 84, duration: 5 * 3600 + 10 * 60,
                previewTracks: ["Blinding Lights", "Sunroof"],
                gradient: [Color(red: 0.2, green: 0.75, blue: 0.7), Color(red: 0.25, green: 0.4, blue: 0.85)]
            ),
            ProposedPlaylist(
                name: "Rock Classics", songCount: 51, duration: 3 * 3600 + 10 * 60,
                previewTracks: ["Redbone"],
                gradient: [Color(red: 0.25, green: 0.25, blue: 0.3), Color(red: 0.55, green: 0.15, blue: 0.2)]
            )
        ],
        .vibe: [
            ProposedPlaylist(
                name: "Late Night Feels", songCount: 38, duration: 2 * 3600 + 12 * 60,
                previewTracks: ["Location", "Adore You", "Snooze"],
                gradient: [Color(red: 0.16, green: 0.2, blue: 0.4), Color(red: 0.35, green: 0.4, blue: 0.6)]
            ),
            ProposedPlaylist(
                name: "Walkout Anthems", songCount: 24, duration: 1 * 3600 + 26 * 60,
                previewTracks: ["No Role Modelz", "Redbone"],
                gradient: [Color(red: 0.85, green: 0.3, blue: 0.2), Color(red: 0.95, green: 0.6, blue: 0.2)]
            ),
            ProposedPlaylist(
                name: "Sunday Morning Chill", songCount: 31, duration: 1 * 3600 + 48 * 60,
                previewTracks: ["Sunroof", "Cruel Summer"],
                gradient: [Color(red: 0.2, green: 0.7, blue: 0.6), Color(red: 0.9, green: 0.8, blue: 0.3)]
            ),
            ProposedPlaylist(
                name: "Workout Energy", songCount: 45, duration: 2 * 3600 + 34 * 60,
                previewTracks: ["Blinding Lights", "Levitating"],
                gradient: [Color(red: 0.9, green: 0.2, blue: 0.25), Color(red: 0.95, green: 0.55, blue: 0.2)]
            ),
            ProposedPlaylist(
                name: "Feel-Good Throwbacks", songCount: 29, duration: 1 * 3600 + 33 * 60,
                previewTracks: ["As It Was", "good 4 u"],
                gradient: [Color(red: 0.9, green: 0.3, blue: 0.55), Color(red: 0.95, green: 0.7, blue: 0.3)]
            ),
            ProposedPlaylist(
                name: "Rainy Day Moods", songCount: 22, duration: 1 * 3600 + 15 * 60,
                previewTracks: ["Take Me Home, Country Roads"],
                gradient: [Color(red: 0.3, green: 0.35, blue: 0.45), Color(red: 0.55, green: 0.6, blue: 0.68)]
            )
        ],
        .artist: [
            ProposedPlaylist(
                name: "The Weeknd", songCount: 18, duration: 3600 + 6 * 60,
                previewTracks: ["Blinding Lights", "Save Your Tears"],
                gradient: [Color(red: 0.85, green: 0.15, blue: 0.2), Color(red: 0.3, green: 0.05, blue: 0.1)]
            ),
            ProposedPlaylist(
                name: "Dua Lipa", songCount: 14, duration: 51 * 60,
                previewTracks: ["Levitating", "Don't Start Now"],
                gradient: [Color(red: 0.95, green: 0.55, blue: 0.75), Color(red: 0.55, green: 0.25, blue: 0.75)]
            ),
            ProposedPlaylist(
                name: "Taylor Swift", songCount: 22, duration: 3600 + 20 * 60,
                previewTracks: ["Cruel Summer", "Anti-Hero"],
                gradient: [Color(red: 0.85, green: 0.7, blue: 0.5), Color(red: 0.6, green: 0.4, blue: 0.5)]
            ),
            ProposedPlaylist(
                name: "J. Cole", songCount: 12, duration: 55 * 60,
                previewTracks: ["No Role Modelz", "Middle Child"],
                gradient: [Color(red: 0.35, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.5, blue: 0.4)]
            ),
            ProposedPlaylist(
                name: "Childish Gambino", songCount: 9, duration: 41 * 60,
                previewTracks: ["Redbone", "This Is America"],
                gradient: [Color(red: 0.5, green: 0.15, blue: 0.15), Color(red: 0.2, green: 0.15, blue: 0.1)]
            ),
            ProposedPlaylist(
                name: "Khalid", songCount: 11, duration: 44 * 60,
                previewTracks: ["Location", "Better"],
                gradient: [Color(red: 0.2, green: 0.4, blue: 0.55), Color(red: 0.35, green: 0.65, blue: 0.7)]
            )
        ]
    ]
}
