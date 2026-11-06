import SwiftUI

/// Drives a pet glyph animation in the menu bar label. Advances one
/// frame every 0.16 s like the Vibe CLI banner. When inactive, the pet
/// freezes on the rest pose. An animator can also rest in its loop: each
/// time the running cycle reaches the rest pose, it stays there for a
/// while, like the original banner.
final class PetAnimator: ObservableObject {
    static let frameInterval = PetAnimation.frameInterval

    /// How long an in-loop rest lasts.
    static let restDelay = PetAnimation.restDelay

    /// When true, the running loop pauses on the rest pose each time it
    /// reaches it (the window banner). When false, the loop is
    /// uninterrupted (the bar, which freezes as a whole when inactive).
    let restsInLoop: Bool

    /// The glyph being animated.
    private(set) var pet: BarPet

    @Published private(set) var frame: Int

    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    init(restsInLoop: Bool = false, pet: BarPet = .chaton) {
        self.restsInLoop = restsInLoop
        self.pet = pet
        self.frame = pet.restFrame
    }

    /// Switches the animated glyph, restarting on its rest pose.
    func setPet(_ newPet: BarPet) {
        guard newPet != pet else { return }
        let wasActive = timer != nil
        timer?.invalidate()
        timer = nil
        pet = newPet
        frame = newPet.restFrame
        setActive(wasActive)
    }

    /// Runs while active, freezes on the rest pose when not.
    func setActive(_ active: Bool) {
        if active {
            if timer == nil {
                if restsInLoop {
                    updateRestingLoop()
                } else {
                    start()
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
            frame = pet.restFrame
        }
    }

    private func tick() {
        frame = pet.nextFrame(after: frame)
    }

    /// Sample the same clock as the widget, including when the banner
    /// reopens or the run loop delays a tick. Neither restarts a cycle.
    private func updateRestingLoop() {
        let now = Date()
        let pose = PetAnimation.pose(at: now, pet: pet)
        frame = pose.frame
        timer = Timer.scheduledTimer(
            withTimeInterval: max(0.001, pose.nextChange.timeIntervalSince(now)),
            repeats: false
        ) { [weak self] _ in
            self?.updateRestingLoop()
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
