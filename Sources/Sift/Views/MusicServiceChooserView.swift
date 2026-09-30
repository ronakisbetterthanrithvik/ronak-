import SwiftUI
import AppKit

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
            chooserAmbientGlow

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
                        imageName: "AppleMusicLogo",
                        fallbackSymbol: "music.note",
                        fallbackGradient: Theme.accentGradient
                    ) {
                        onChoose(.appleMusic)
                    }

                    serviceCard(
                        title: "Spotify",
                        subtitle: "Coming soon",
                        imageName: "SpotifyLogo",
                        fallbackSymbol: "waveform",
                        fallbackGradient: Self.spotifyGradient
                    ) {
                        onChoose(.spotify)
                    }
                }
            }
            .padding(40)
        }
    }

    /// Only shown on this chooser screen -- both services are still an open choice here,
    /// so the ambient glow carries both brand colors (Sift's own red plus Spotify's
    /// green). The moment a service is actually picked, every other screen goes back to
    /// `Theme.ambientGlow`'s plain red, with no green at all.
    private var chooserAmbientGlow: some View {
        ZStack {
            Circle()
                .fill(Theme.accentPrimary.opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(x: -260, y: -180)
            Circle()
                .fill(Theme.accentSecondary.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 140)
                .offset(x: -100, y: 80)
            Circle()
                .fill(Self.spotifyGreen.opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(x: 260, y: -180)
            Circle()
                .fill(Self.spotifyGreen.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 140)
                .offset(x: 100, y: 80)
        }
    }

    static let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)
    static let spotifyGreenDark = Color(red: 0.05, green: 0.4, blue: 0.2)

    static let spotifyGradient = LinearGradient(
        colors: [spotifyGreen, spotifyGreenDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private func serviceCard(
        title: String,
        subtitle: String,
        imageName: String,
        fallbackSymbol: String,
        fallbackGradient: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                brandIcon(named: imageName, fallbackSymbol: fallbackSymbol, fallbackGradient: fallbackGradient)

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

/// Loads a bundled logo file by name (an already-square app icon like Apple Music's or
/// Spotify's own mark, dropped into the app bundle the same way `Theme.appIcon` loads
/// `SiftIcon.png` -- no asset catalog entry required), falling back to a plain SF Symbol
/// tile in the brand's gradient if the file hasn't been added to the Xcode target yet.
@ViewBuilder
func brandIcon(named imageName: String, fallbackSymbol: String, fallbackGradient: LinearGradient, size: CGFloat = 72) -> some View {
    if let nsImage = NSImage(named: imageName) {
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    } else {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fallbackGradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: fallbackSymbol).font(.system(size: size * 0.39)).foregroundStyle(.white))
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
                brandIcon(
                    named: "SpotifyLogo",
                    fallbackSymbol: "waveform",
                    fallbackGradient: MusicServiceChooserView.spotifyGradient,
                    size: 84
                )

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
