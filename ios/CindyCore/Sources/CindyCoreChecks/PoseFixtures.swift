import Foundation
import CindyCore

/// Synthetic keypoint bodies, so the rep logic can be exercised without a camera.
/// Coordinates are in "pixels" with y growing downward, matching what the detector emits.
enum PoseFixtures {

    static let limb: Float = 100
    static let torso: Float = 100

    private static func blank() -> [Keypoint] { Array(repeating: .missing, count: KP.count) }

    private static func putPair(_ k: inout [Keypoint], _ left: Int, _ right: Int,
                                _ x: Float, _ y: Float) {
        k[left] = Keypoint(x: x - 10, y: y, score: 0.9)
        k[right] = Keypoint(x: x + 10, y: y, score: 0.9)
    }

    private static func rad(_ deg: Float) -> Float { deg * .pi / 180 }

    /// A body squatting with the given knee angle. 180 is standing, 90 is below parallel.
    static func squat(_ kneeDeg: Float) -> [Keypoint] {
        var k = blank()
        let hipX = limb * sinf(rad(kneeDeg))
        let hipY = limb * cosf(rad(kneeDeg))
        putPair(&k, KP.leftKnee, KP.rightKnee, 0, 0)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, 0, limb)
        putPair(&k, KP.leftHip, KP.rightHip, hipX, hipY)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, hipX, hipY - torso)
        k[KP.nose] = Keypoint(x: hipX, y: hipY - torso - 30, score: 0.9)
        return k
    }

    /// A body mid push-up with the given elbow angle. 180 is lockout, 90 is chest down.
    static func pushup(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = limb * sinf(rad(elbowDeg))
        let shY = limb * cosf(rad(elbowDeg))
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, limb)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        putPair(&k, KP.leftHip, KP.rightHip, shX - torso, shY)
        putPair(&k, KP.leftKnee, KP.rightKnee, shX - torso - 80, shY)
        return k
    }

    /// A body on the bar with the given elbow angle. 170 is a dead hang, 60 is chin over the bar.
    /// The shoulders rise past the hands at the top, exactly as they do on a real pull-up.
    static func pullup(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = limb * sinf(rad(elbowDeg))
        let shY = -limb * cosf(rad(elbowDeg))
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, -limb)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        putPair(&k, KP.leftHip, KP.rightHip, shX, shY + torso)
        k[KP.nose] = Keypoint(x: shX, y: shY - 20, score: 0.9)
        return k
    }

    /// Nothing confidently detected — the "step into frame" case.
    static func empty() -> [Keypoint] { blank() }
}

/// Drives an engine the way a camera would.
final class Rig {
    let engine = WorkoutEngine()
    var clock: Int64 = 0

    func hold(_ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames {
            _ = engine.onFrame(pose, now: clock)
            clock += 100
        }
    }

    @discardableResult
    func setupHold(_ pose: [Keypoint], frames: Int = 10) -> Setup {
        var last = engine.onSetupFrame(pose, now: clock)
        for _ in 0..<frames {
            last = engine.onSetupFrame(pose, now: clock)
            clock += 100
        }
        return last
    }

    func pullup(hang: Float = 170, top: Float = 60) {
        hold(PoseFixtures.pullup(hang))
        hold(PoseFixtures.pullup(top))
    }

    func pushup() {
        hold(PoseFixtures.pushup(80))
        hold(PoseFixtures.pushup(175))
    }

    func squat() {
        hold(PoseFixtures.squat(80))
        hold(PoseFixtures.squat(175))
    }
}
