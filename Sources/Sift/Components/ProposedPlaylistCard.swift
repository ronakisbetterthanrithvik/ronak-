import SwiftUI

struct ProposedPlaylistCard: View {
    @Binding var proposal: ProposedPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: proposal.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)

                Spacer()

                Button {
                    proposal.isSelected.toggle()
                } label: {
                    Image(systemName: proposal.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(proposal.isSelected ? Theme.accentSecondary : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Text(proposal.name)
                .font(.system(size: 15, weight: .semibold))

            Text("\(proposal.songCount) songs · \(proposal.duration.asHoursMinutesString)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(proposal.previewTracks.joined(separator: ", ") + "…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(proposal.isSelected ? 0.05 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(proposal.isSelected ? Theme.accentPrimary.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
