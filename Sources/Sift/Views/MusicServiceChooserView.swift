import SwiftUI

enum MusicServiceChoice: String {
    case appleMusic
    case spotify
}

/// The very first screen on a fresh install -- lets a person pick which streaming
/// service Sift should connect to before anything else happens, so the two are never
/// ambiguous. Apple Music continues straight into the existing MusicKit connect flow.
/// Spotify support (real playlist read/write plus controlling the Spotify desktop app
/// for playback) is being built but isn't wired up yet, so picking it shows
/// `SpotifyComingSoonView` instead of pretending to connect.
struct MusicServiceChooserView: View {
    var onChoose: (MusicServiceChoice) -> Void

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 36) {
                VStack(spacing: 8) {
                    Text("Welcome to Sift")
                        .font(.system(size: 30, weight: .bold))
                    Text("Choose the music service you want Sift to connect to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    serviceCard(
                        title: "Apple Music",
                        subtitle: "Library, Auto-Sort, Vibe, and the AI Playlist Generator",
                        icon: "music.note",
                        gradient: Theme.accentGradient
                    ) {
                        onChoose(.appleMusic)
                    }

                    serviceCard(
                        title: "Spotify",
                        subtitle: "Coming soon",
                        icon: "waveform",
                        gradient: Self.spotifyGradient
                    ) {
                        onChoose(.spotify)
                    }
                }
            }
            .padding(40)
        }
    }

    static let spotifyGradient = LinearGradient(
        colors: [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.05, green: 0.4, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private func serviceCard(
        title: String,
        subtitle: String,
        icon: String,
        gradient: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(gradient)
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.white))

                VStack(spacing: 6) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 160)
                }
            }
            .padding(24)
            .frame(width: 220, height: 220)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Shown after picking Spotify on the chooser above, since real Spotify support isn't
/// built yet -- says so plainly instead of silently doing nothing, and offers a way into
/// the one fully working path (Apple Music) without restarting the app.
struct SpotifyComingSoonView: View {
    var onUseAppleMusicInstead: () -> Void

    var body: some View {
        ZStack {
            Theme.background
            Theme.ambientGlow

            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MusicServiceChooserView.spotifyGradient)
                    .frame(width: 84, height: 84)
                    .overlay(Image(systemName: "waveform").font(.system(size: 32)).foregroundStyle(.white))

                VStack(spacing: 8) {
                    Text("Spotify support is on the way")
                        .font(.title2.bold())
                    Text("Sift doesn't connect to Spotify yet, but it's being built -- full playlist access, Auto-Sort, Vibe, and the AI Playlist Generator, working the same way they do for Apple Music.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                Button(action: onUseAppleMusicInstead) {
                    Text("Use Apple Music Instead")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Theme.accentGradient))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
    }
}
