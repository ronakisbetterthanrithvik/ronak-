import MusicKit
import SwiftUI
import AppKit

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
    @State private var showSiftPlaylists = false
    @State private var confirmationMessage: String?
    @StateObject private var siftPlaylists = SiftPlaylistStore.shared

    /// One `CreateSiftPlaylistView` prompt per Auto-Sort proposal the person just
    /// selected to create -- `currentCreation` drives the sheet, and each Create/Skip
    /// advances to the next queued proposal (or finishes once the queue is empty).
    @State private var creationQueue: [ProposedPlaylist] = []
    @State private var currentCreation: ProposedPlaylist?

    @AppStorage("hasSeenWelcomeDisclaimer") private var hasSeenWelcomeDisclaimer = false
    @State private var showWelcomeDisclaimer = false

    private var showsAdvancedTools: Bool { playlist.songCount >= 25 }

    /// Sift's own local-only playlists (see `SiftOwnedPlaylist`) shown first in the
    /// carousel, ahead of real Apple Music library playlists -- freshly created ones
    /// should be easy to find right after creating them.
    private var pickablePlaylists: [PickablePlaylist] {
        siftPlaylists.playlists.map { .sift($0) } + libraryPlaylists.map { .library($0) }
    }

    var body: some View {
        Group {
            switch stage {
            case .connecting:
                ConnectView(status: authorizationDisplay, onConnect: connectToAppleMusic, onUseDemoData: useDemoData)
            case .pickingPlaylist:
                PlaylistPickerView(
                    playlists: pickablePlaylists,
                    isLoading: isLoadingLibrary,
                    errorMessage: libraryError,
                    onSelect: { picked in
                        switch picked {
                        case .library(let summary): selectPlaylist(summary)
                        case .sift(let owned): selectSiftPlaylist(owned)
                        }
                    },
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
        .sheet(item: $currentCreation) { proposal in
            CreateSiftPlaylistView(
                proposal: proposal,
                onCreate: { name, coverImage in
                    let created = siftPlaylists.create(name: name, songLibraryIDs: proposal.songLibraryIDs, coverImage: coverImage)
                    announce("Created “\(name)” in Sift")
                    if creationQueue.isEmpty {
                        // Nothing else queued behind this one -- go straight to the new
                        // playlist's own screen instead of leaving the person back on
                        // whatever playlist Auto-Sort was run on.
                        currentCreation = nil
                        selectSiftPlaylist(created)
                    } else {
                        advanceCreationQueue()
                    }
                },
                onSkip: { advanceCreationQueue() }
            )
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
                .padding(.bottom, nowPlayingSong == nil ? 0 : 70)
            }

            // A plain bottom overlay instead of `.safeAreaInset(edge: .bottom)` -- that
            // modifier on a macOS ScrollView has a known quirk where it can swallow
            // trackpad scroll events instead of forwarding them to the scroll view, which
            // broke scrolling on this screen entirely. This gets the same "docked at the
            // bottom, doesn't scroll away" result (with the extra bottom padding above so
            // the last few rows aren't hidden behind it) without touching the ScrollView's
            // own event handling -- the empty space around the compact pill has no content
            // of its own, so trackpad scrolling still passes through to the list beneath it.
            VStack {
                Spacer()
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
                guard !isDemoMode else {
                    announce("Created \(selected.count) playlist\(selected.count == 1 ? "" : "s") (demo — not saved)")
                    return
                }
                creationQueue = selected
            }
        }
        // Auto-Sort's own sheet has to actually close before the first naming/cover
        // prompt opens, or SwiftUI ends up trying to present two sheets from this view
        // at once -- this starts the queue right as that dismiss finishes, rather than
        // inside AutoSortView's own onCreate callback above.
        .onChange(of: showAutoSort) { isShowing in
            if !isShowing { advanceCreationQueue() }
        }
        .sheet(isPresented: $showQueue) {
            QueueView(playback: playback)
        }
        .sheet(isPresented: $showSiftPlaylists) {
            SiftPlaylistsView(store: siftPlaylists) { saved in
                Task {
                    await playSiftPlaylist(saved)
                    showSiftPlaylists = false
                }
            }
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

    /// Opens a Sift-only playlist the same way `selectPlaylist` opens a real library
    /// one -- resolving its songs by id (works across relaunches, not just within the
    /// session it was created in; see `MusicLibraryService.resolveSongs`) and building
    /// the same kind of `SiftPlaylist` the rest of this screen already knows how to show.
    private func selectSiftPlaylist(_ owned: SiftOwnedPlaylist) {
        Task {
            isLoadingLibrary = true
            libraryError = nil
            let songs = await MusicLibraryService.shared.resolveSongs(forLibraryIDs: owned.songLibraryIDs)
            guard !songs.isEmpty else {
                libraryError = "None of those songs were found in your library anymore."
                isLoadingLibrary = false
                return
            }

            var artistCounts: [String: Int] = [:]
            for song in songs {
                for artistName in song.artist.splitArtistCredits() {
                    artistCounts[artistName, default: 0] += 1
                }
            }
            let topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(4).map(\.key)

            let loaded = SiftPlaylist(
                libraryID: nil,
                name: owned.name,
                ownerName: "Sift",
                songCount: songs.count,
                totalDuration: songs.reduce(0) { $0 + $1.duration },
                songs: songs,
                genresPresent: Array(Set(songs.map(\.genre))).sorted(),
                topArtists: Array(topArtists),
                allArtists: Array(artistCounts.keys).sorted(),
                artwork: nil,
                mosaicArtwork: Array(songs.compactMap(\.artwork).prefix(4)),
                localArtworkImage: siftPlaylists.coverImage(for: owned)
            )
            playlist = loaded
            smartControlSettings = SmartControlSettings.default(for: loaded)
            autoSortProposals = [
                .genre: AutoSortEngine.genreGroups(from: songs),
                .artist: AutoSortEngine.artistGroups(from: songs),
                .vibe: []
            ]
            isDemoMode = false
            stage = .ready
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
            if let localImage = playlist.localArtworkImage {
                Image(nsImage: localImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let artwork = playlist.artwork {
                // A playlist's own custom cover can be any photo someone picked, unlike
                // a song's own artwork -- give it room to not be a perfect square.
                squareArtwork(artwork, size: 120, overscan: 1.5)
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

            Button { showSiftPlaylists = true } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("My Sift Playlists")
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

    /// Apple's on-device MusicKit doesn't support creating playlists on Mac (confirmed
    /// via a real Xcode compiler error — iOS/iPadOS only), so Auto-Sort proposals are
    /// saved as Sift-only playlists instead, each named and given a cover via
    /// `CreateSiftPlaylistView` first -- playable from the wand button in this screen's
    /// action row and shown right in the "Choose a Playlist" carousel, just never
    /// written into Apple Music itself.
    private func advanceCreationQueue() {
        currentCreation = creationQueue.isEmpty ? nil : creationQueue.removeFirst()
    }

    private func playSiftPlaylist(_ saved: SiftOwnedPlaylist) async {
        let songs = await MusicLibraryService.shared.resolveSongs(forLibraryIDs: saved.songLibraryIDs)
        guard !songs.isEmpty else {
            announce("None of those songs were found in your library anymore.")
            return
        }
        do {
            try await playback.playInOrder(songs)
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
                                Text(song.displayTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(song.displayArtist)
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
                    Text(song.displayTitle)
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
                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary)
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
