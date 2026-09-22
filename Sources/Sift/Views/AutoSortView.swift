import SwiftUI

struct AutoSortView: View {
    let playlist: Playlist
    @Binding var proposalsByMode: [AutoSortMode: [ProposedPlaylist]]
    var onCreate: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: AutoSortMode = .genre

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var proposals: [ProposedPlaylist] { proposalsByMode[mode] ?? [] }
    private var selectedCount: Int { proposals.filter { $0.isSelected }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            tabBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(proposals.indices, id: \.self) { index in
                            ProposedPlaylistCard(proposal: bindingForProposal(at: index))
                        }
                    }
                }
                .padding(24)
            }

            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 760, height: 640)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
                onCreate(selectedCount)
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
