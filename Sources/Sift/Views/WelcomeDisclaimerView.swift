import SwiftUI

/// Shown once, the first time Sift launches, before the connect flow — sets
/// expectations honestly rather than letting Smart Control's UI imply it already
/// knows your listening habits.
struct WelcomeDisclaimerView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(.white))

            VStack(spacing: 8) {
                Text("Before you start")
                    .font(.title2.bold())
                Text("Two things worth knowing about how Sift actually works.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                disclaimerRow(
                    icon: "clock.arrow.circlepath",
                    title: "Smart Control starts cold",
                    body: "Apple doesn't let third-party apps see your past Apple Music listening history. Smart Control only learns from plays and skips that happen inside Sift — so at first, Shuffle behaves like a normal shuffle no matter where you set the Familiarity dial. It gets more accurate the more you actually use Sift to play music."
                )
                disclaimerRow(
                    icon: "square.stack.3d.up",
                    title: "Auto-Sort works right away",
                    body: "Genre and Artist sorting are built from your songs' real metadata, not listening history, so those work correctly from the very first time you use them."
                )
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.accentGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(36)
        .frame(maxWidth: 480)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func disclaimerRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accentSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}
