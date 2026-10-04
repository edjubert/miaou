import SwiftUI

/// Drives the petit chat animation in the menu bar label. Advances one
/// frame every 0.16 s like the Vibe CLI banner, rests 5 to 20 s on the
/// rest pose (state 26), and sometimes (25%) pauses mid-cycle on the
/// frames where the original does, with the head settled and eyes open.
final class ChatonAnimator: ObservableObject {
    static let frameInterval: TimeInterval = 0.16
    static let restFrames: Set<Int> = [5, 11, 21, 24]
    static let pauseDelay: ClosedRange<Double> = 5...20

    @Published private(set) var frame = 0

    private var timer: Timer?

    /// Runs while active, freezes on the reference pose when not.
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
            frame = 0
        }
    }

    private func tick() {
        if frame == Chaton.frames.count - 1 {
            // Rest pose: the cycle loops back into its second state.
            frame = 1
            pause()
        } else {
            frame += 1
            if Self.restFrames.contains(frame),
               Double.random(in: 0...1) < 0.25 {
                pause()
            }
        }
    }

    private func pause() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: Self.pauseDelay),
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(
                withTimeInterval: Self.frameInterval,
                repeats: true
            ) { [weak self] _ in
                self?.tick()
            }
        }
    }
}
