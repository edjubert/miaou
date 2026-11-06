import SwiftUI

/// Drives a pet glyph animation in the menu bar label. Advances one
/// frame every 0.16 s like the Vibe CLI banner. When inactive, the pet
/// freezes on the rest pose. An animator can also rest in its loop: each
/// time the running cycle reaches the rest pose, it stays there for a
/// while, like the original banner.
final class PetAnimator: ObservableObject {
    static let frameInterval: TimeInterval = Chaton.frameInterval

    /// How long an in-loop rest lasts.
    static let restDelay: ClosedRange<Double> = 5...20

    /// When true, the running loop pauses on the rest pose each time it
    /// reaches it (the window banner). When false, the loop is
    /// uninterrupted (the bar, which freezes as a whole when inactive).
    let restsInLoop: Bool

    /// The glyph being animated.
    private(set) var pet: BarPet

    @Published private(set) var frame: Int

    private var timer: Timer?

    init(restsInLoop: Bool = false, pet: BarPet = .chaton) {
        self.restsInLoop = restsInLoop
        self.pet = pet
        self.frame = pet.restFrame
    }

    /// Switches the animated glyph, restarting on its rest pose.
    func setPet(_ newPet: BarPet) {
        guard newPet != pet else { return }
        pet = newPet
        frame = newPet.restFrame
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
            frame = pet.restFrame
        }
    }

    private func tick() {
        frame = pet.nextFrame(after: frame)
        if restsInLoop && frame == pet.restFrame {
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
