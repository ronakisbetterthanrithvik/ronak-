import SwiftUI

struct ConnectView: View {
    let status: MusicAuthorizationStatusDisplay
    var onConnect: () -> Void
    var onUseDemoData: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "music.note").font(.system(size: 32)).foregroundStyle(.white))

            VStack(spacing: 8) {
                Text("Connect Apple Music")
                    .font(.title2.bold())
                Text(status.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: onConnect) {
                Text(status.actionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!status.canRetry)

            Button("Use demo data instead", action: onUseDemoData)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Maps `MusicAuthorization.Status` to the copy/actions this screen shows,
/// kept separate from the MusicKit type so this file doesn't need `import MusicKit`.
struct MusicAuthorizationStatusDisplay {
    let message: String
    let actionTitle: String
    let canRetry: Bool

    static let notDetermined = MusicAuthorizationStatusDisplay(
        message: "Sift reads your Apple Music playlists to power Smart Control and Auto-Sort. Nothing plays or changes until you connect.",
        actionTitle: "Connect Apple Music",
        canRetry: true
    )

    static let denied = MusicAuthorizationStatusDisplay(
        message: "Apple Music access was denied. Enable it in System Settings → Privacy & Security → Media & Apple Music, then come back here.",
        actionTitle: "Try Again",
        canRetry: true
    )

    static let restricted = MusicAuthorizationStatusDisplay(
        message: "Apple Music access is restricted on this Mac (parental controls or an MDM profile), so Sift can't connect here.",
        actionTitle: "Restricted",
        canRetry: false
    )
}
