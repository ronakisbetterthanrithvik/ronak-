import SwiftUI
import MusicKit

struct PlaylistPickerView: View {
    let playlists: [PickablePlaylist]
    let isLoading: Bool
    let errorMessage: String?
    var onSelect: (PickablePlaylist) -> Void
    var onRetry: () -> Void

    @State private var selectedIndex = 0
    @State private var dragTranslation: CGFloat = 0

    private enum Cover {
        case single(Artwork)
        case mosaic([Artwork])
        // Not "none" -- that would collide with Optional<Cover>.none when switching over
        // `covers[id]` (a Cover?), silently making this case unreachable.
        case unavailable
    }

    /// Each real library playlist's cover, fetched lazily (via
    /// `MusicLibraryService.loadPlaylistCoverArtwork`) only for playlists the carousel
    /// actually scrolls to, and cached here so none is ever fetched twice. Sift-only
    /// playlists don't need this -- their cover (if any) is already a local file, read
    /// synchronously via `SiftPlaylistStore.coverImage(for:)`.
    @State private var covers: [String: Cover] = [:]

    /// How many tiles show on either side of the selected one before they're clipped off.
    private let sideWindow = 2
    private let tileSpacing: CGFloat = 190

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.ambientGlow.ignoresSafeArea()

            VStack(spacing: 28) {
                header

                if isLoading {
                    Spacer()
                    ProgressView("Loading your playlists…")
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry", action: onRetry)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .glassSurface(Capsule())
                    }
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if playlists.isEmpty {
                    Spacer()
                    Text("No playlists found in your Apple Music library yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    Spacer()
                    carousel
                    arrows
                    Spacer()
                    Text("Pick a playlist to open -- your Apple Music library, or one Sift created.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 36)
                }
            }
        }
        .onChange(of: playlists) { _ in selectedIndex = 0 }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Playlist")
                    .font(.system(size: 30, weight: .bold))
            }
            Spacer()
            Theme.appIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        }
        .padding(.top, 28)
        .padding(.horizontal, 32)
    }

    // MARK: - Carousel

    private var carousel: some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { index in
                tile(for: playlists[index], offset: index - selectedIndex)
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var visibleIndices: [Int] {
        (-sideWindow...sideWindow).compactMap { delta in
            let index = selectedIndex + delta
            return playlists.indices.contains(index) ? index : nil
        }
    }

    private func tile(for item: PickablePlaylist, offset: Int) -> some View {
        let isSelected = offset == 0
        let distance = abs(offset)
        let size: CGFloat = isSelected ? 220 : (distance == 1 ? 160 : 108)
        let dimOpacity = isSelected ? 1.0 : (distance == 1 ? 0.55 : 0.26)
        let xOffset = CGFloat(offset) * tileSpacing + dragTranslation

        return VStack(spacing: 10) {
            artwork(for: item, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 22, y: 14)

            if isSelected {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 240)
            }
        }
        .opacity(dimOpacity)
        .offset(x: xOffset)
        .zIndex(isSelected ? 1 : 0)
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isSelected {
                    onSelect(item)
                } else if let tappedIndex = playlists.firstIndex(where: { $0.id == item.id }) {
                    selectedIndex = tappedIndex
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in dragTranslation = value.translation.width }
            .onEnded { value in
                let threshold: CGFloat = 60
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if value.translation.width < -threshold {
                        selectedIndex = min(selectedIndex + 1, playlists.count - 1)
                    } else if value.translation.width > threshold {
                        selectedIndex = max(selectedIndex - 1, 0)
                    }
                    dragTranslation = 0
                }
            }
    }

    @ViewBuilder
    private func artwork(for item: PickablePlaylist, size: CGFloat) -> some View {
        switch item {
        case .library(let summary):
            switch covers[summary.id] {
            case .single(let artwork):
                // A playlist's own custom cover can be any photo someone picked, unlike
                // a song's own artwork -- give it room to not be a perfect square.
                squareArtwork(artwork, size: size, overscan: 1.5)
            case .mosaic(let artworks):
                mosaic(artworks, size: size)
            case .unavailable:
                artworkPlaceholder.frame(width: size, height: size)
            case nil:
                artworkPlaceholder
                    .frame(width: size, height: size)
                    .task { await loadCover(for: summary) }
            }
        case .sift(let owned):
            if let nsImage = SiftPlaylistStore.shared.coverImage(for: owned) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                artworkPlaceholder.frame(width: size, height: size)
            }
        }
    }

    private func loadCover(for summary: LibraryPlaylistSummary) async {
        guard covers[summary.id] == nil else { return }
        let result = await MusicLibraryService.shared.loadPlaylistCoverArtwork(id: summary.id)
        if let single = result.single {
            covers[summary.id] = .single(single)
        } else if !result.mosaic.isEmpty {
            covers[summary.id] = .mosaic(result.mosaic)
        } else {
            covers[summary.id] = .unavailable
        }
    }

    /// Matches how Apple Music itself covers a personal playlist with no custom artwork:
    /// a 2x2 grid of album art sampled from the playlist's own songs.
    private func mosaic(_ artworks: [Artwork], size: CGFloat) -> some View {
        let tiles: [Artwork?] = (0..<4).map { $0 < artworks.count ? artworks[$0] : nil }
        let tileSize = size / 2
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                mosaicTile(tiles[0], size: tileSize)
                mosaicTile(tiles[1], size: tileSize)
            }
            GridRow {
                mosaicTile(tiles[2], size: tileSize)
                mosaicTile(tiles[3], size: tileSize)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func mosaicTile(_ artwork: Artwork?, size: CGFloat) -> some View {
        if let artwork {
            squareArtwork(artwork, size: size)
        } else {
            Theme.accentGradient
                .frame(width: size, height: size)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentGradient)
            .overlay(Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(.white.opacity(0.9)))
    }

    // MARK: - Arrows

    private var arrows: some View {
        HStack(spacing: 28) {
            arrowButton(systemName: "chevron.left", disabled: selectedIndex == 0) {
                selectedIndex = max(selectedIndex - 1, 0)
            }
            arrowButton(systemName: "chevron.right", disabled: selectedIndex >= playlists.count - 1) {
                selectedIndex = min(selectedIndex + 1, playlists.count - 1)
            }
        }
    }

    private func arrowButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 52, height: 52)
                .glassSurface(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}
