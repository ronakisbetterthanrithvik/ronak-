import SwiftUI

struct PlaylistDetailView: View {
    @State private var playlist = Playlist.everything
    @State private var smartControlSettings = SmartControlSettings.default(for: Playlist.everything)
    @State private var autoSortProposals = AutoSortStore.proposals

    @State private var showSmartControl = false
    @State private var showAutoSort = false
    @State private var confirmationMessage: String?

    private var showsAdvancedTools: Bool { playlist.songCount >= 25 }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
        .frame(minWidth: 900, minHeight: 640)
        .sheet(isPresented: $showSmartControl) {
            SmartControlView(playlist: playlist, settings: $smartControlSettings) { _ in
                announce("Smart Control updated")
            }
        }
        .sheet(isPresented: $showAutoSort) {
            AutoSortView(playlist: playlist, proposalsByMode: $autoSortProposals) { createdCount in
                announce("Created \(createdCount) playlist\(createdCount == 1 ? "" : "s")")
            }
        }
    }

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

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentGradient)
            .frame(width: 120, height: 120)
            .overlay(Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)))
            .shadow(color: Theme.accentPrimary.opacity(0.4), radius: 20, y: 10)
    }

    private var appBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Theme.accentSecondary)
            Text("Works with Apple Music")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {} label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {} label: {
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

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(playlist.sampleSongs.enumerated()), id: \.element.id) { index, song in
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

            HStack(spacing: 6) {
                Image(systemName: "ellipsis.circle")
                Text("Showing \(playlist.sampleSongs.count) of \(playlist.songCount) songs")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
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
