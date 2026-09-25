import SwiftUI

/// A brief animated intro shown once each time the app launches, before the real
/// content appears -- the Sift mark scales in, a prism ring (the same rainbow-glass
/// identity used for the rest of the app's glass surfaces) sweeps around it, then the
/// whole thing fades out to reveal whatever screen the app is actually opening to.
struct LaunchSplashView: View {
    var onFinished: () -> Void

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var ringOpacity: Double = 0
    @State private var isFadingOut = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(Theme.prismGradient, lineWidth: 3)
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(ringRotation))
                    .opacity(ringOpacity)
                    .blur(radius: 0.5)

                Theme.appIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.accentPrimary.opacity(0.5), radius: 24, y: 8)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
        }
        .opacity(isFadingOut ? 0 : 1)
        .onAppear(perform: animate)
    }

    private func animate() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
            iconScale = 1.0
            iconOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            ringOpacity = 1
        }
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.45)) {
                isFadingOut = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onFinished()
            }
        }
    }
}
