import SwiftUI

/// Browses and plays the playlists Sift has created for itself (Auto-Sort proposals,
/// Vibe results) -- these can't be written into Apple Music (see
/// `MusicLibraryService.resolveSongs`), so this is the only place to reach them again
/// after the moment they're created.
struct SiftPlaylistsView: View {
    @ObservedObject var store: SiftPlaylistStore
    var onPlay: (SiftOwnedPlaylist) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isResolving: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            if store.playlists.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Sift playlists yet")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Auto-Sort's Genre, Artist, and Vibe proposals get saved here once you create them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.playlists) { playlist in
                        row(for: playlist)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 460, height: 560)
        .background(.ultraThinMaterial)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Sift Playlists").font(.title3.bold())
                Text("Created here, played here — not in Apple Music")
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

    private func row(for playlist: SiftOwnedPlaylist) -> some View {
        Button {
            isResolving = playlist.id
            onPlay(playlist)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Group {
                            if isResolving == playlist.id {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "wand.and.stars").foregroundStyle(.white)
                            }
                        }
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(playlist.songLibraryIDs.count) songs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.delete(id: playlist.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
