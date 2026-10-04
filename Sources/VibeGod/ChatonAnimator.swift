import SwiftUI

/// Drives the petit chat animation in the menu bar label. Advances one
/// frame every 0.16 s like the Vibe CLI banner, in one continuous loop
/// over the cycle states: no pauses. When inactive, the chaton freezes
/// on the rest pose.
final class ChatonAnimator: ObservableObject {
    static let frameInterval: TimeInterval = 0.16

    /// The pose the chaton freezes on when it does not move.
    static let restFrame = 14

    @Published private(set) var frame = ChatonAnimator.restFrame

    private var timer: Timer?

    /// Next state in the cycle. The animation is periodic on states
    /// 1...26: after the last state, the first transition brings back
    /// the second one. State 0 is only the departure pose.
    static func nextFrame(after frame: Int) -> Int {
        frame == Chaton.frames.count - 1 ? 1 : frame + 1
    }

    /// Runs while active, freezes on the rest pose when not.
    func setActive(_ active: Bool) {
        if active {
            if timer == nil {
                timer = Timer.scheduledTimer(
                    withTimeInterval: Self.frameInterval,
                    repeats: true
                ) { [weak self] _ in
                    self?.tick()
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
            frame = Self.restFrame
        }
    }

    private func tick() {
        frame = Self.nextFrame(after: frame)
    }
}
