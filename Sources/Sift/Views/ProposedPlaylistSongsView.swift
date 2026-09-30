import SwiftUI

/// Shown when you tap an Auto-Sort proposal card (Genre, Vibe, or Artist) -- the full
/// song list behind that proposal, with a way to drop any song you don't want before
/// actually creating the playlist. Edits here write straight back into the proposal
/// (via the `@Binding`), so they're reflected in the card's own song count/duration/
/// preview the moment this sheet closes.
struct ProposedPlaylistSongsView: View {
    @Binding var proposal: ProposedPlaylist
    let allSongs: [SiftSong]

    @Environment(\.dismiss) private var dismiss

    /// The proposal's own songs, resolved from its library IDs and kept in the same
    /// order -- `ProposedPlaylist` only stores ids, not full `SiftSong`s.
    ///
    /// `Dictionary(_:uniquingKeysWith:)`, not `Dictionary(uniqueKeysWithValues:)` -- a
    /// real Apple Music playlist can have the same song appear more than once, which
    /// made the "unique keys" version crash outright (`Fatal error: Duplicate values
    /// for key`) the moment a playlist with a repeated track was opened.
    private var songs: [SiftSong] {
        let byID = Dictionary(allSongs.map { ($0.libraryID, $0) }, uniquingKeysWith: { first, _ in first })
        return proposal.songLibraryIDs.compactMap { byID[$0] }
    }

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))

                if songs.isEmpty {
                    Spacer()
                    Text("No songs left in this proposal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(songs) { song in
                            row(song)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .frame(width: 460, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.name).font(.title3.bold())
                Text("\(proposal.songCount) songs · \(proposal.duration.asHoursMinutesString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private func row(_ song: SiftSong) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(song.duration.asClockString).font(.caption).foregroundStyle(.secondary)
            Button {
                remove(song)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Drops the song from the proposal and re-derives the summary fields
    /// (`songCount`/`duration`/`previewTracks`) from what's left, rather than leaving
    /// them stale until the proposal is recomputed from scratch elsewhere.
    private func remove(_ song: SiftSong) {
        proposal.songLibraryIDs.removeAll { $0 == song.libraryID }
        let remaining = songs
        proposal.songCount = remaining.count
        proposal.duration = remaining.reduce(0) { $0 + $1.duration }
        proposal.previewTracks = Array(remaining.prefix(3).map(\.title))
    }
}
