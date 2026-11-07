import Foundation

/// The menu banner and desktop widget use the same clock and poses.
/// A reproducible sequence of varied pauses lets separate processes
/// agree on the animation without restarting it on a widget reload.
enum PetAnimation {
    static let frameInterval: TimeInterval = 0.16
    /// How long the pet sleeps on its rest pose: 40 s to 2 min. The pauses
    /// come from a seeded sequence, so every process agrees on them.
    static let restDelay: ClosedRange<Double> = 40...120

    struct Pose {
        let frame: Int
        let nextChange: Date
    }

    private struct Step {
        let frame: Int
        let endMilliseconds: Int64
    }

    // Millisecond offsets avoid accumulating fractional-frame drift.
    // The sequence repeats only after 64 full animation/rest cycles.
    private static let schedules: [BarPet: [Step]] = Dictionary(
        uniqueKeysWithValues: BarPet.allCases.map { ($0, makeSteps(pet: $0)) }
    )

    private static func makeSteps(pet: BarPet) -> [Step] {
        let frameMilliseconds = Int64((frameInterval * 1_000).rounded())
        let minimumRest = Int64(restDelay.lowerBound * 1_000)
        let restRange = UInt64((restDelay.upperBound - restDelay.lowerBound) * 1_000) + 1
        var seed: UInt64 = 0x4D_49_41_4F_55
        var end: Int64 = 0
        var result: [Step] = []
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let rest = minimumRest + Int64((seed >> 32) % restRange)
            var frame = pet.restFrame
            repeat {
                // The old banner waited for its rest timer and then
                // one frame interval before opening its eyes again.
                end += frameMilliseconds + (frame == pet.restFrame ? rest : 0)
                result.append(Step(frame: frame, endMilliseconds: end))
                frame = pet.nextFrame(after: frame)
            } while frame != pet.restFrame
        }
        return result
    }

    static func pose(at date: Date, pet: BarPet = .chaton) -> Pose {
        let steps = schedules[pet]!
        let period = steps.last!.endMilliseconds
        let milliseconds = Int64((date.timeIntervalSinceReferenceDate * 1_000).rounded())
        let phase = ((milliseconds % period) + period) % period
        let step = steps.first { phase < $0.endMilliseconds }!
        let next = milliseconds - phase + step.endMilliseconds
        return Pose(frame: step.frame,
                    nextChange: Date(timeIntervalSinceReferenceDate: Double(next) / 1_000))
    }
}
