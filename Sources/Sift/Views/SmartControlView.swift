import SwiftUI

struct SmartControlView: View {
    let playlist: SiftPlaylist
    @Binding var settings: SmartControlSettings
    var onApply: (SmartControlSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SmartControlSettings

    init(playlist: SiftPlaylist, settings: Binding<SmartControlSettings>, onApply: @escaping (SmartControlSettings) -> Void) {
        self.playlist = playlist
        self._settings = settings
        self.onApply = onApply
        _draft = State(initialValue: settings.wrappedValue)
    }

    private var pinnedArtists: [String] { playlist.topArtists }
    private var moreArtists: [String] {
        playlist.allArtists.filter { !pinnedArtists.contains($0) && !draft.selectedArtists.contains($0) }
    }
    private var extraSelectedArtists: [String] {
        draft.selectedArtists.filter { !pinnedArtists.contains($0) }.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    familiaritySection
                    signalsSection
                    genresSection
                    artistsSection
                }
                .padding(24)
            }

            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 640, height: 620)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "slider.horizontal.3").foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Control").font(.title3.bold())
                Text("\(playlist.name) · \(playlist.songCount) songs")
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

    private var familiaritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Familiarity").font(.headline)
                Spacer()
                Text("Which songs Shuffle reaches for first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FamiliaritySlider(value: $draft.familiarity) { newValue in
                draft.applyFamiliarityPreset(for: newValue)
            }

            HStack {
                Text("Rarely Played").foregroundStyle(Theme.rarelyPlayed)
                Spacer()
                Text("Balanced").foregroundStyle(.secondary)
                Spacer()
                Text("Most Played").foregroundStyle(Theme.mostPlayed)
            }
            .font(.system(size: 12, weight: .semibold))

            Text(draft.familiarityCaption)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentPrimary.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.accentPrimary.opacity(0.4), lineWidth: 1))
        }
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How Shuffle listens to you").font(.headline)
                Text("Turn each signal up or down — this is what actually drives the Familiarity dial above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                ForEach($draft.signals) { $signal in
                    SignalRow(signal: $signal)
                }
            }
        }
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Genres").font(.headline)
                Text("Only shuffle within selected genres — leave empty to include all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(playlist.genresPresent, id: \.self) { genre in
                    Chip(label: genre, isSelected: draft.selectedGenres.contains(genre)) {
                        toggle(genre, in: &draft.selectedGenres)
                    }
                }
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Artists").font(.headline)
                Text("Include only these artists when shuffling — optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(pinnedArtists, id: \.self) { artist in
                    Chip(label: artist, isSelected: draft.selectedArtists.contains(artist)) {
                        toggle(artist, in: &draft.selectedArtists)
                    }
                }
                ForEach(extraSelectedArtists, id: \.self) { artist in
                    Chip(label: artist, isSelected: true) {
                        toggle(artist, in: &draft.selectedArtists)
                    }
                }

                Menu {
                    ForEach(moreArtists, id: \.self) { artist in
                        Button(artist) { draft.selectedArtists.insert(artist) }
                    }
                } label: {
                    Label("Add Artist", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(moreArtists.isEmpty)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Default") {
                draft = SmartControlSettings.default(for: playlist)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white)

            Button {
                settings = draft
                onApply(draft)
                dismiss()
            } label: {
                Text("Apply")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
