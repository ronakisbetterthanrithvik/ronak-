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
                    onUseDemoData: useDemoData,
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

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    backButton
                    header
                    actionRow
                    trackList
                }
                .padding(28)
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
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentGradient)
            .frame(width: 120, height: 120)
            .overlay(Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)))
            .shadow(color: Theme.accentPrimary.opacity(0.4), radius: 20, y: 10)
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
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { Task { await playTapped() } } label: {
                Label("Play", systemImage: "play.fill")
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
                    .background(Capsule().fill(Color.white.opacity(0.08)))
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
            .background(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Track list

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                HStack {
                    Text("\(index + 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.system(size: 14, weight: .medium))
                        Text(song.artist).font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(song.album)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(song.duration.asClockString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    private func announce(_ message: String) {
        withAnimation { confirmationMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { confirmationMessage = nil }
        }
    }
}
