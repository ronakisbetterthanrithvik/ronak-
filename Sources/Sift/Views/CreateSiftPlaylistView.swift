import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Shown once per playlist Auto-Sort is about to create -- lets you rename it and
/// optionally pick a local photo as its cover, since a Sift-only playlist (see
/// `SiftOwnedPlaylist`) has no real Apple Music artwork to fall back on the way an
/// actual library playlist does.
///
/// Presentation (including advancing to the next queued proposal, or finishing) is
/// entirely owned by the caller via `onCreate`/`onSkip` -- this view never dismisses
/// itself, so chaining several of these back to back (one per selected proposal) is a
/// simple matter of the caller changing which proposal it's showing.
struct CreateSiftPlaylistView: View {
    let proposal: ProposedPlaylist
    var onCreate: (String, NSImage?) -> Void
    var onSkip: () -> Void

    @State private var name: String
    @State private var coverImage: NSImage?
    /// The just-picked photo, still awaiting a crop confirm/cancel -- separate from
    /// `coverImage` so a cancelled crop leaves whatever cover was already set untouched.
    @State private var pendingCropImage: NSImage?

    init(proposal: ProposedPlaylist, onCreate: @escaping (String, NSImage?) -> Void, onSkip: @escaping () -> Void) {
        self.proposal = proposal
        self.onCreate = onCreate
        self.onSkip = onSkip
        _name = State(initialValue: proposal.name)
    }

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text("New Sift Playlist")
                        .font(.title3.bold())
                    Text("Saved in Sift only -- not written to Apple Music")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                coverPicker

                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    TextField("Playlist name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.4)))
                        .glassEdge(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(maxWidth: 260)

                Text("\(proposal.songCount) songs · \(proposal.duration.asHoursMinutesString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("Skip", action: onSkip)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmed.isEmpty ? proposal.name : trimmed, coverImage)
                    } label: {
                        Text("Create")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.accentGradient))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
        .frame(width: 420, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), lineWidth: 1.25)
        .sheet(isPresented: Binding(
            get: { pendingCropImage != nil },
            set: { isPresented in if !isPresented { pendingCropImage = nil } }
        )) {
            if let pendingCropImage {
                ImageCropPickerView(
                    image: pendingCropImage,
                    onConfirm: { cropped in
                        coverImage = cropped
                        self.pendingCropImage = nil
                    },
                    onCancel: { self.pendingCropImage = nil }
                )
            }
        }
    }

    private var coverPicker: some View {
        Button(action: pickCoverImage) {
            Group {
                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: proposal.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 26))
                                Text("Add Cover")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        )
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pickCoverImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        pendingCropImage = image
    }
}
