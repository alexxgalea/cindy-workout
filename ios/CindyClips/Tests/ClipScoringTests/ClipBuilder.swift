import Foundation
import CindyCore
import CindyFixtures
import ClipScoring

/// Builds the frames of a clip out of the synthetic bodies the engine's own tests use, at the
/// pace the engine tests use: ten frames a pose, one every 100 ms.
struct ClipBuilder {
    var frames: [ClipFrame] = []
    var clock: Int64 = 0
    let width = 720
    let height = 1280
    /// Where in the frame the body is. The fixtures are drawn about the origin, which is off
    /// the picture; a clip that has to be scored against a bar in the picture moves them in.
    var shift: (dx: Float, dy: Float) = (0, 0)

    mutating func hold(_ pose: [Keypoint], frames count: Int = 10, tracking: Bool = true) {
        for _ in 0..<count {
            let placed = shift == (0, 0) ? pose : pose.moved(dx: shift.dx, dy: shift.dy)
            frames.append(ClipFrame(timestampMs: clock, width: width, height: height,
                                    trackingStable: tracking, keypoints: placed))
            clock += 100
        }
    }

    /// Hang, then pull to the top: one pull-up.
    mutating func pullup(hang: Float = 170, top: Float = 60) {
        hold(PoseFixtures.pullup(hang))
        hold(PoseFixtures.pullup(top))
    }

    /// Lockout, bottom, lockout.
    mutating func pushup() {
        hold(PoseFixtures.pushup(175))
        hold(PoseFixtures.pushup(80))
        hold(PoseFixtures.pushup(175))
    }

    mutating func squat() {
        hold(PoseFixtures.squat(175))
        hold(PoseFixtures.squat(80))
        hold(PoseFixtures.squat(175))
    }

    mutating func pullups(_ n: Int) { for _ in 0..<n { pullup() } ; hold(PoseFixtures.pullup(170)) }
    mutating func pushups(_ n: Int) { for _ in 0..<n { pushup() } }
    mutating func squats(_ n: Int) { for _ in 0..<n { squat() } }
}
