import SwiftUI

struct PlaylistPickerView: View {
    let playlists: [LibraryPlaylistSummary]
    let isLoading: Bool
    let errorMessage: String?
    var onSelect: (LibraryPlaylistSummary) -> Void
    var onUseDemoData: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Playlist")
                    .font(.title2.bold())
                Text("Pick which Apple Music library playlist Sift should open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

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
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white)
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
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(playlists) { playlist in
                            Button {
                                onSelect(playlist)
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(Theme.accentSecondary)
                                    Text(playlist.name)
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }

            Button("Use demo data instead", action: onUseDemoData)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background)
    }
}
