import SwiftUI
import MusicKit

struct QueueView: View {
    @ObservedObject var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    private var nowPlaying: SiftSong? { playback.queuedSongs.first }
    private var upNext: [SiftSong] { Array(playback.queuedSongs.dropFirst()) }

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))

                if let nowPlaying {
                    nowPlayingSection(nowPlaying)
                    Divider().overlay(Color.white.opacity(0.08))
                }

                if upNext.isEmpty {
                    Text("Nothing queued after this.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("UP NEXT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                        .padding(.top, 16)
                        .padding(.horizontal, 20)

                    // A real List (not a plain ForEach in a ScrollView) so drag-to-reorder
                    // works with macOS's own animated reordering -- dragging a row here
                    // slides the others out of the way, then settles the queue in the new
                    // order once you drop it.
                    List {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, song in
                            queueRow(song, queueIndex: offset + 1)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        }
                        .onMove { source, destination in
                            playback.moveQueuedSongs(fromUpNextOffsets: source, toUpNextOffset: destination)
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
            Text("Queue").font(.title3.bold())
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

    private func nowPlayingSection(_ song: SiftSong) -> some View {
        VStack(spacing: 16) {
            Text("NOW PLAYING")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .frame(maxWidth: .infinity, alignment: .leading)

            artwork(for: song, size: 120)
                .shadow(color: Theme.accentPrimary.opacity(0.35), radius: 16, y: 8)

            VStack(spacing: 4) {
                Text(song.title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if playback.isPlaying {
                        EqualizerBars(isPlaying: true)
                    }
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                Button { Task { await playback.skipToPrevious() } } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 40, height: 40)
                        .glassSurface(Circle())
                }

                Button {
                    if playback.isPlaying {
                        playback.pause()
                    } else {
                        Task { try? await playback.resume() }
                    }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                }

                Button { Task { await playback.skipToNext() } } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 40, height: 40)
                        .glassSurface(Circle())
                }
                .disabled(playback.queuedSongs.count <= 1)
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEdge(RoundedRectangle(cornerRadius: 16, style: .continuous), lineWidth: 1, baseOpacity: 0.4)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func queueRow(_ song: SiftSong, queueIndex: Int) -> some View {
        HStack(spacing: 12) {
            artwork(for: song, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(song.duration.asClockString).font(.caption).foregroundStyle(.secondary)
            Button {
                playback.removeFromQueue(at: queueIndex)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func artwork(for song: SiftSong, size: CGFloat) -> some View {
        if let artwork = song.artwork {
            squareArtwork(artwork, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            artworkPlaceholder
                .frame(width: size, height: size)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.accentGradient.opacity(0.5))
            .overlay(Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)))
    }
}
