import MusicKit
import SwiftUI

private enum Stage {
    case connecting
    case pickingPlaylist
    case ready
}

struct PlaylistDetailView: View {
    @StateObject private var auth = MusicAuthorizationService.shared
    @StateObject private var playback = PlaybackService.shared

    @State private var stage: Stage = .connecting
    @State private var isDemoMode = true

    @State private var libraryPlaylists: [LibraryPlaylistSummary] = []
    @State private var isLoadingLibrary = false
    @State private var libraryError: String?

    @State private var playlist = SiftPlaylist.everything
    @State private var smartControlSettings = SmartControlSettings.default(for: SiftPlaylist.everything)
    @State private var autoSortProposals = AutoSortStore.proposals

    @State private var showSmartControl = false
    @State private var showAutoSort = false
    @State private var showQueue = false
    @State private var confirmationMessage: String?

    @AppStorage("hasSeenWelcomeDisclaimer") private var hasSeenWelcomeDisclaimer = false
    @State private var showWelcomeDisclaimer = false

    private var showsAdvancedTools: Bool { playlist.songCount >= 25 }

    var body: some View {
        Group {
            switch stage {
            case .connecting:
                ConnectView(status: authorizationDisplay, onConnect: connectToAppleMusic, onUseDemoData: useDemoData)
            case .pickingPlaylist:
                PlaylistPickerView(
                    playlists: libraryPlaylists,
                    isLoading: isLoadingLibrary,
                    errorMessage: libraryError,
                    onSelect: { selectPlaylist($0) },
                    onRetry: { Task { await loadLibraryPlaylists() } }
                )
            case .ready:
                readyContent
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .sheet(isPresented: $showWelcomeDisclaimer) {
            WelcomeDisclaimerView {
                hasSeenWelcomeDisclaimer = true
                showWelcomeDisclaimer = false
            }
        }
        .task {
            if !hasSeenWelcomeDisclaimer {
                showWelcomeDisclaimer = true
            }
            auth.refreshStatus()
            if auth.isAuthorized {
                await loadLibraryPlaylists()
            }
        }
    }

    private var readyContent: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            Theme.ambientGlow.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    backButton
                    header
                    actionRow
                    trackList
                }
                .padding(28)
            }
            .safeAreaInset(edge: .bottom) {
                nowPlayingBar
            }

            if let message = confirmationMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSmartControl) {
            SmartControlView(playlist: playlist, settings: $smartControlSettings) { _ in
                announce("Smart Control updated")
            }
        }
        .sheet(isPresented: $showAutoSort) {
            AutoSortView(playlist: playlist, proposalsByMode: $autoSortProposals) { selected in
                Task { await createPlaylists(selected) }
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView(playback: playback)
        }
    }

    // MARK: - Apple Music connection

    private var authorizationDisplay: MusicAuthorizationStatusDisplay {
        switch auth.status {
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    private func connectToAppleMusic() {
        Task {
            let status = await auth.requestAccess()
            if status == .authorized {
                await loadLibraryPlaylists()
            }
        }
    }

    private func loadLibraryPlaylists() async {
        stage = .pickingPlaylist
        isLoadingLibrary = true
        libraryError = nil
        do {
            libraryPlaylists = try await MusicLibraryService.shared.fetchPlaylists()
        } catch {
            libraryError = error.localizedDescription
        }
        isLoadingLibrary = false
    }

    private func selectPlaylist(_ summary: LibraryPlaylistSummary) {
        Task {
            isLoadingLibrary = true
            libraryError = nil
            do {
                let loaded = try await MusicLibraryService.shared.loadPlaylist(id: summary.id)
                playlist = loaded
                smartControlSettings = SmartControlSettings.default(for: loaded)
                autoSortProposals = [
                    .genre: AutoSortEngine.genreGroups(from: loaded.songs),
                    .artist: AutoSortEngine.artistGroups(from: loaded.songs),
                    .vibe: []
                ]
                isDemoMode = false
                stage = .ready
            } catch {
                libraryError = error.localizedDescription
                isLoadingLibrary = false
            }
        }
    }

    private func useDemoData() {
        playlist = .everything
        smartControlSettings = SmartControlSettings.default(for: .everything)
        autoSortProposals = AutoSortStore.proposals
        isDemoMode = true
        stage = .ready
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            artwork

            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text(playlist.name)
                    .font(.system(size: 34, weight: .bold))
                Text("\(playlist.ownerName) · \(playlist.songCount) songs · \(playlist.totalDuration.asHoursMinutesString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            appBadge
        }
    }

    private var backButton: some View {
        Button {
            if isDemoMode {
                stage = .connecting
            } else {
                Task { await loadLibraryPlaylists() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text(isDemoMode ? "Connect Apple Music" : "Back to Playlists")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassSurface(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        Group {
            if let artwork = playlist.artwork {
                // A playlist's own custom cover can be any photo someone picked, unlike
                // a song's own artwork -- give it room to not be a perfect square.
                squareArtwork(artwork, size: 120, overscan: 2)
            } else if !playlist.mosaicArtwork.isEmpty {
                artworkMosaic
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.accentPrimary.opacity(0.4), radius: 20, y: 10)
    }

    /// Matches how Apple Music itself covers a personal playlist with no custom artwork:
    /// a 2x2 grid of album art from the playlist's own songs. Pads with the placeholder
    /// tile if fewer than 4 song artworks were actually available.
    private var artworkMosaic: some View {
        let available = playlist.mosaicArtwork
        let tiles: [Artwork?] = (0..<4).map { index in index < available.count ? available[index] : nil }
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                mosaicTile(tiles[0])
                mosaicTile(tiles[1])
            }
            GridRow {
                mosaicTile(tiles[2])
                mosaicTile(tiles[3])
            }
        }
    }

    @ViewBuilder
    private func mosaicTile(_ artwork: Artwork?) -> some View {
        if let artwork {
            squareArtwork(artwork, size: 60)
        } else {
            Theme.accentGradient
                .frame(width: 60, height: 60)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentGradient)
            .overlay(Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)))
    }

    private var appBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: isDemoMode ? "eye.fill" : "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Theme.accentSecondary)
            Text(isDemoMode ? "Demo data — not connected" : "Connected to Apple Music")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(Capsule())
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if playback.isPlaying {
                    playback.pause()
                } else {
                    Task { await playTapped() }
                }
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button { Task { await shuffleTapped() } } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .glassSurface(Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if showsAdvancedTools {
                toolButton(title: "Smart Control", icon: "slider.horizontal.3") { showSmartControl = true }
                toolButton(title: "Auto-Sort", icon: "square.stack.3d.up") { showAutoSort = true }
            }

            Spacer()
        }
    }

    private func playTapped() async {
        guard !isDemoMode else {
            announce("Connect Apple Music to actually play songs")
            return
        }
        do {
            try await playback.playInOrder(playlist.songs)
        } catch {
            print("Sift DEBUG: playTapped failed — \(error)")
            announce(error.localizedDescription)
        }
    }

    private func shuffleTapped() async {
        guard !isDemoMode else {
            announce("Connect Apple Music to actually play songs")
            return
        }
        do {
            try await playback.shufflePlay(playlist.songs, settings: smartControlSettings)
        } catch {
            print("Sift DEBUG: shuffleTapped failed — \(error)")
            announce(error.localizedDescription)
        }
    }

    private func createPlaylists(_ proposals: [ProposedPlaylist]) async {
        guard !isDemoMode else {
            announce("Created \(proposals.count) playlist\(proposals.count == 1 ? "" : "s") (demo — not saved)")
            return
        }
        do {
            for proposal in proposals {
                try await MusicLibraryService.shared.createPlaylist(name: proposal.name, songLibraryIDs: proposal.songLibraryIDs)
            }
            announce("Created \(proposals.count) playlist\(proposals.count == 1 ? "" : "s") in Apple Music")
        } catch {
            announce(error.localizedDescription)
        }
    }

    private var nowPlayingSong: SiftSong? {
        guard let id = playback.nowPlayingLibraryID else { return nil }
        return playlist.songs.first { $0.libraryID == id }
    }

    /// A persistent mini transport bar docked to the bottom of the window, the same spot
    /// Apple Music's own player bar sits -- shuffle/back/play/forward on the left, the
    /// now-playing song in the middle (tap it to open the Queue), a Queue button on the
    /// right, and a thin progress line underneath. It's attached via `.safeAreaInset`
    /// rather than living inside the scrolling content, so it stays put while the track
    /// list scrolls underneath it, but stays a compact floating pill rather than a
    /// full-width bar.
    @ViewBuilder
    private var nowPlayingBar: some View {
        if let song = nowPlayingSong {
            VStack(spacing: 6) {
                HStack(spacing: 20) {
                    HStack(spacing: 18) {
                        Button { Task { await shuffleTapped() } } label: {
                            Image(systemName: "shuffle")
                        }
                        Button { Task { await playback.skipToPrevious() } } label: {
                            Image(systemName: "backward.fill")
                        }
                        Button {
                            if playback.isPlaying {
                                playback.pause()
                            } else {
                                Task { try? await playback.resume() }
                            }
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Button { Task { await playback.skipToNext() } } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))

                    Button { showQueue = true } label: {
                        HStack(spacing: 10) {
                            rowArtwork(for: song, size: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if playback.isPlaying {
                                EqualizerBars(isPlaying: true)
                            }
                        }
                        .contentShape(Rectangle())
                    }

                    Button { showQueue = true } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                playbackProgressLine(for: song)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.92)))
            .padding(.bottom, 16)
        }
    }

    /// Polls `playback.currentPlaybackTime` on a half-second tick -- MusicKit doesn't
    /// publish elapsed time as a Combine value, so this is the simplest way to keep the
    /// line moving without Sift maintaining its own timer/state for it.
    private func playbackProgressLine(for song: SiftSong) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * progressFraction(for: song))
                }
            }
        }
        .frame(height: 3)
    }

    private func progressFraction(for song: SiftSong) -> Double {
        guard song.duration > 0 else { return 0 }
        return min(max(playback.currentPlaybackTime / song.duration, 0), 1)
    }

    private func toolButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .semibold))
                Text("NEW")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentSecondary))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassSurface(Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Track list

    private var trackList: some View {
        VStack(spacing: 0) {
            trackListHeader
            LazyVStack(spacing: 0) {
                ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                    let isNowPlaying = song.libraryID == playback.nowPlayingLibraryID

                    trackRow(song: song, index: index, isNowPlaying: isNowPlaying)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await songTapped(song) }
                        }
                }
            }
        }
        .padding(16)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), lineWidth: 1.25)
    }

    private var trackListHeader: some View {
        HStack(spacing: 12) {
            Text("SONG")
                .frame(width: 332, alignment: .leading)
            Text("ALBUM")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TIME")
                .frame(width: 50, alignment: .trailing)
            Color.clear.frame(width: 20)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.secondary)
        .tracking(1.2)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func trackRow(song: SiftSong, index: Int, isNowPlaying: Bool) -> some View {
        HStack(spacing: 12) {
            rowArtwork(for: song, size: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isNowPlaying ? Theme.accentSecondary : .primary)
                        .lineLimit(1)
                    if isNowPlaying {
                        if playback.isPlaying {
                            EqualizerBars(isPlaying: true)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accentSecondary)
                        }
                    }
                }
                Text(song.artist).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 280, alignment: .leading)

            Text(song.album)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(song.duration.asClockString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            Menu {
                Button("Play Next") { Task { await enqueueTapped(song, playNext: true) } }
                Button("Add to Queue") { Task { await enqueueTapped(song, playNext: false) } }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isNowPlaying ? Theme.accentPrimary.opacity(0.16) : Color.clear)
        )
        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous), lineWidth: 0.75, baseOpacity: isNowPlaying ? 0.4 : 0.22)
    }

    @ViewBuilder
    private func rowArtwork(for song: SiftSong, size: CGFloat) -> some View {
        if let artwork = song.artwork {
            squareArtwork(artwork, size: size)
        } else {
            rowArtworkPlaceholder.frame(width: size, height: size)
        }
    }

    private var rowArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.accentGradient.opacity(0.5))
            .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)))
    }

    private func songTapped(_ song: SiftSong) async {
        guard !isDemoMode else {
            announce("Connect Apple Music to actually play songs")
            return
        }
        do {
            if song.libraryID == playback.nowPlayingLibraryID {
                if playback.isPlaying {
                    playback.pause()
                } else {
                    try await playback.resume()
                }
            } else {
                try await playback.play(song, from: playlist.songs)
            }
        } catch {
            announce(error.localizedDescription)
        }
    }

    private func enqueueTapped(_ song: SiftSong, playNext: Bool) async {
        guard !isDemoMode else {
            announce("Connect Apple Music to actually queue songs")
            return
        }
        do {
            try await playback.enqueue(song, playNext: playNext)
            announce(playNext ? "Playing next" : "Added to queue")
        } catch {
            announce(error.localizedDescription)
        }
    }

    private func announce(_ message: String) {
        withAnimation { confirmationMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { confirmationMessage = nil }
        }
    }
}
