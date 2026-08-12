import Lottie
import SwiftUI

/// Full-screen confetti celebration used for tutorial graduation.
struct ConfettiCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion, let animation = loadAnimation() {
            LottieView(animation: animation)
                .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
                .animationSpeed(1)
                .configure(\.contentMode, to: .scaleAspectFill)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func loadAnimation() -> LottieAnimation? {
        if let path = Bundle.main.path(forResource: "confetti", ofType: "json", inDirectory: "Lottie") {
            return LottieAnimation.filepath(path)
        }
        return LottieAnimation.named("confetti")
    }
}
