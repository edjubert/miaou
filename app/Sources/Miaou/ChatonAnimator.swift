import SwiftUI

/// Drives the petit chat animation in the menu bar label. Advances one
/// frame every 0.16 s like the Vibe CLI banner. When inactive, the
/// chaton freezes on the rest pose. An animator can also rest in its
/// loop: each time the running cycle reaches the rest pose, it stays
/// there for a while, like the original banner.
final class ChatonAnimator: ObservableObject {
    static let frameInterval: TimeInterval = 0.16

    /// The pose the chaton freezes on when it does not move: head down,
    /// eyes closed.
    static let restFrame = 14

    /// How long an in-loop rest lasts.
    static let restDelay: ClosedRange<Double> = 5...20

    /// When true, the running loop pauses on the rest pose each time it
    /// reaches it (the window banner). When false, the loop is
    /// uninterrupted (the bar, which freezes as a whole when inactive).
    let restsInLoop: Bool

    @Published private(set) var frame = ChatonAnimator.restFrame

    private var timer: Timer?

    init(restsInLoop: Bool = false) {
        self.restsInLoop = restsInLoop
    }

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
                start()
            }
        } else {
            timer?.invalidate()
            timer = nil
            frame = Self.restFrame
        }
    }

    private func tick() {
        frame = Self.nextFrame(after: frame)
        if restsInLoop && frame == Self.restFrame {
            rest()
        }
    }

    /// Stays on the rest pose for a while, then runs again.
    private func rest() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: Self.restDelay),
            repeats: false
        ) { [weak self] _ in
            self?.start()
        }
    }

    private func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.frameInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tick()
        }
    }
}
