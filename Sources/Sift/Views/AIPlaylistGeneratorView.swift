import SwiftUI

/// "AI Playlist Generator" -- reached from a banner on the "Choose a Playlist" carousel
/// screen, not from Auto-Sort. Unlike Auto-Sort's Vibe tab (which only ever curates from
/// a playlist you already have open), this builds a brand new playlist from anywhere in
/// Apple Music's catalog based on a free-text request alone. See
/// `CatalogPlaylistGeneratorService` for the suggest-then-verify pipeline behind it.
struct AIPlaylistGeneratorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var requestText = ""
    @State private var isGenerating = false
    @State private var generationError: String?

    @State private var proposal: ProposedPlaylist?
    @State private var resolvedSongs: [SiftSong] = []
    @State private var currentCreation: ProposedPlaylist?

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))

                if let proposal {
                    reviewContent(proposal)
                } else {
                    requestContent
                }
            }
        }
        .frame(width: 520, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
        .sheet(item: $currentCreation) { toCreate in
            CreateSiftPlaylistView(
                proposal: toCreate,
                onCreate: { name, coverImage in
                    SiftPlaylistStore.shared.create(name: name, songLibraryIDs: toCreate.songLibraryIDs, coverImage: coverImage)
                    currentCreation = nil
                    dismiss()
                },
                onSkip: { currentCreation = nil }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "sparkles").foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Playlist Generator").font(.title3.bold())
                Text("Built from anywhere in Apple Music's catalog")
                    .font(.subheadline)
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

    // MARK: - Request step

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe a playlist -- any mood, activity, or artists -- and Sift searches all of Apple Music for real songs to match, not just what's already in your library.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $requestText)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(height: 120)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 12)

                if requestText.isEmpty {
                    Text("e.g. \"Upbeat 2010s indie rock for a road trip\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))

            if let generationError {
                Text(generationError)
                    .font(.caption)
                    .foregroundStyle(Theme.accentSecondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    generate()
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isGenerating ? "Searching Apple Music…" : "Generate")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating || requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func generate() {
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isGenerating = true
        generationError = nil
        Task {
            do {
                let result = try await CatalogPlaylistGeneratorService.generate(request: trimmed)
                resolvedSongs = result.songs
                proposal = AutoSortEngine.vibeProposal(name: result.name, songs: result.songs)
            } catch {
                generationError = error.localizedDescription
            }
            isGenerating = false
        }
    }

    // MARK: - Review step

    private func reviewContent(_ current: ProposedPlaylist) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.name).font(.headline)
                Text("\(current.songCount) songs · \(current.duration.asHoursMinutesString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            List {
                ForEach(songsInProposal(current)) { song in
                    songRow(song)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Button("Start Over") {
                    proposal = nil
                    resolvedSongs = []
                    requestText = ""
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white)

                Spacer()

                Button {
                    currentCreation = current
                } label: {
                    Text("Create Playlist")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(current.songCount == 0 ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.accentGradient))
                        )
                        .foregroundStyle(current.songCount == 0 ? .white.opacity(0.4) : .white)
                }
                .buttonStyle(.plain)
                .disabled(current.songCount == 0)
            }
            .padding(20)
        }
    }

    private func songsInProposal(_ current: ProposedPlaylist) -> [SiftSong] {
        let idsInProposal = Set(current.songLibraryIDs)
        return resolvedSongs.filter { idsInProposal.contains($0.libraryID) }
    }

    private func songRow(_ song: SiftSong) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(song.duration.asClockString).font(.caption).foregroundStyle(.secondary)
            Button {
                removeSong(song)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Drops the song from the proposal and re-derives the summary fields, same as
    /// `ProposedPlaylistSongsView` does for an Auto-Sort proposal.
    private func removeSong(_ song: SiftSong) {
        guard var current = proposal else { return }
        current.songLibraryIDs.removeAll { $0 == song.libraryID }
        let remaining = songsInProposal(current)
        current.songCount = remaining.count
        current.duration = remaining.reduce(0) { $0 + $1.duration }
        current.previewTracks = Array(remaining.prefix(3).map(\.title))
        proposal = current
    }
}
