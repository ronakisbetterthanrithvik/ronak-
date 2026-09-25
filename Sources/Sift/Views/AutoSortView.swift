import SwiftUI

struct AutoSortView: View {
    let playlist: SiftPlaylist
    @Binding var proposalsByMode: [AutoSortMode: [ProposedPlaylist]]
    var onCreate: ([ProposedPlaylist]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: AutoSortMode = .genre

    @State private var hasAPIKey = AnthropicAPIKeyStore.load() != nil
    @State private var apiKeyInput = ""
    @State private var vibeRequestText = ""
    @State private var isGeneratingVibe = false
    @State private var vibeError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var proposals: [ProposedPlaylist] { proposalsByMode[mode] ?? [] }
    private var selectedCount: Int { proposals.filter { $0.isSelected }.count }

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))
                tabBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(mode.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if !proposals.isEmpty {
                                Button(selectedCount == proposals.count ? "Deselect All" : "Select All") {
                                    let makeSelected = selectedCount != proposals.count
                                    proposalsByMode[mode] = proposals.map {
                                        var proposal = $0
                                        proposal.isSelected = makeSelected
                                        return proposal
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accentSecondary)
                            }
                        }

                        if mode == .vibe {
                            vibeControls
                        }

                        if proposals.isEmpty {
                            if mode != .vibe {
                                Text("Nothing to propose yet.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 24)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(proposals.indices, id: \.self) { index in
                                    ProposedPlaylistCard(proposal: bindingForProposal(at: index))
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                Divider().overlay(Color.white.opacity(0.08))
                footer
            }
        }
        .frame(width: 760, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
    }

    // MARK: - Vibe

    @ViewBuilder
    private var vibeControls: some View {
        if !hasAPIKey {
            apiKeyEntry
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    // TextEditor carries its own small built-in inset on top of whatever
                    // padding is set here (there's no public way to zero it out), so this
                    // is shaved down from the placeholder's padding below to land the
                    // cursor roughly where the placeholder text starts -- nudge these two
                    // padding values together if it's still off after rebuilding.
                    TextEditor(text: $vibeRequestText)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(height: 90)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)

                    if vibeRequestText.isEmpty {
                        Text("e.g. \"Give me a playlist with only NBA YoungBoy and Lil Uzi Vert, plus some other hype songs from this playlist\"")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))

                if let vibeError {
                    Text(vibeError)
                        .font(.caption)
                        .foregroundStyle(Theme.accentSecondary)
                }

                HStack {
                    Button("Use a different API key") {
                        hasAPIKey = false
                        apiKeyInput = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        generateVibePlaylist()
                    } label: {
                        HStack(spacing: 6) {
                            if isGeneratingVibe {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text(isGeneratingVibe ? "Thinking…" : "Generate")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accentGradient))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingVibe || vibeRequestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var apiKeyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vibe uses Claude, Anthropic's AI, to understand a free-text request like this — add your own Anthropic API key to use it. It's stored in the macOS Keychain and sent only to Anthropic's API, never anywhere else.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("Anthropic API key", text: $apiKeyInput)
                .textFieldStyle(.plain)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))

            Button("Save Key") {
                AnthropicAPIKeyStore.save(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                hasAPIKey = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.accentGradient))
            .foregroundStyle(.white)
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func generateVibePlaylist() {
        let request = vibeRequestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        isGeneratingVibe = true
        vibeError = nil
        Task {
            do {
                let result = try await ClaudeVibeService.curatePlaylist(request: request, from: playlist.songs)
                let matchedIDs = Set(result.songLibraryIDs)
                let matchedSongs = playlist.songs.filter { matchedIDs.contains($0.libraryID) }
                proposalsByMode[.vibe] = [AutoSortEngine.vibeProposal(name: result.name, songs: matchedSongs)]
            } catch {
                vibeError = error.localizedDescription
            }
            isGeneratingVibe = false
        }
    }

    private func bindingForProposal(at index: Int) -> Binding<ProposedPlaylist> {
        Binding(
            get: { proposalsByMode[mode]?[index] ?? proposals[index] },
            set: { newValue in proposalsByMode[mode]?[index] = newValue }
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "square.stack.3d.up").foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Sort").font(.title3.bold())
                Text("Split \(playlist.name) into new playlists")
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

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(AutoSortMode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    HStack(spacing: 6) {
                        Text(candidate.rawValue)
                        if candidate == .vibe {
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(mode == candidate ? Theme.accentPrimary : Color.clear))
                    .foregroundStyle(mode == candidate ? .white : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Text("\(selectedCount) of \(proposals.count) playlists selected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white)

            Button {
                onCreate(proposals.filter(\.isSelected))
                dismiss()
            } label: {
                Text("Create Playlists")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(selectedCount == 0 ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.accentGradient))
                    )
                    .foregroundStyle(selectedCount == 0 ? .white.opacity(0.4) : .white)
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
        }
        .padding(20)
    }
}
