import Foundation
import CindyCore

/// Synthetic keypoint bodies, so the rep logic can be exercised without a camera.
/// Coordinates are in "pixels" with y growing downward, matching what the detector emits.
public enum PoseFixtures {

    public static let limb: Float = 100
    public static let torso: Float = 100

    private static func blank() -> [Keypoint] { Array(repeating: .missing, count: KP.count) }

    private static func putPair(_ k: inout [Keypoint], _ left: Int, _ right: Int,
                                _ x: Float, _ y: Float) {
        k[left] = Keypoint(x: x - 10, y: y, score: 0.9)
        k[right] = Keypoint(x: x + 10, y: y, score: 0.9)
    }

    /// Kotlin's `Math.toRadians(deg.toDouble())`: Java's constant, in `Double`.
    private static func rad(_ deg: Float) -> Double { Double(deg) * 0.017453292519943295 }

    /// Kotlin's `(LIMB * sin(rad(x))).toFloat()`: the product and the sine are `Double`, and the
    /// result is rounded to `Float` once. Working them in `Float` moves a coordinate by a bit,
    /// which the parity trace's `kpSum` column exists to catch.
    private static func swing(_ length: Float, _ trig: (Double) -> Double, _ deg: Float) -> Float {
        Float(Double(length) * trig(rad(deg)))
    }

    /// A body squatting with the given knee angle. 180 is standing, 90 is below parallel.
    public static func squat(_ kneeDeg: Float) -> [Keypoint] {
        var k = blank()
        let hipX = swing(limb, sin, kneeDeg)
        let hipY = swing(limb, cos, kneeDeg)
        putPair(&k, KP.leftKnee, KP.rightKnee, 0, 0)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, 0, limb)
        putPair(&k, KP.leftHip, KP.rightHip, hipX, hipY)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, hipX, hipY - torso)
        k[KP.nose] = Keypoint(x: hipX, y: hipY - torso - 30, score: 0.9)
        return k
    }

    /// A body face down on the floor at the end of a set of push-ups, legs straight.
    ///
    /// The knee angle here is a full 180 degrees, the same reading a standing body gives, so this
    /// is the pose that proves a squat cannot be gated on leg extension alone. What separates it
    /// from standing is the torso, which lies along the floor instead of pointing up.
    public static func onTheFloor() -> [Keypoint] {
        var k = blank()
        putPair(&k, KP.leftShoulder, KP.rightShoulder, 0, 0)
        putPair(&k, KP.leftHip, KP.rightHip, -torso, 0)
        // Hip, knee and ankle collinear along the floor: the legs are locked out.
        putPair(&k, KP.leftKnee, KP.rightKnee, -torso - 80, 0)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, -torso - 160, 0)
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, limb)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, 2 * limb)
        k[KP.nose] = Keypoint(x: 60, y: 0, score: 0.9)
        return k
    }

    /// A body mid push-up with the given elbow angle. 180 is lockout, 90 is chest down.
    public static func pushup(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = swing(limb, sin, elbowDeg)
        let shY = swing(limb, cos, elbowDeg)
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, limb)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        putPair(&k, KP.leftHip, KP.rightHip, shX - torso, shY)
        putPair(&k, KP.leftKnee, KP.rightKnee, shX - torso - 80, shY)
        return k
    }

    /// A body on the bar with the given elbow angle. 170 is a dead hang, 60 is chin over the bar.
    /// The shoulders rise past the hands at the top, exactly as they do on a real pull-up.
    ///
    /// Nose is the head proxy emitted by COCO-17. At the top it must pass the wrist/bar line; at
    /// a dead hang it is below the reset line. Keeping that distinction in the shared fixture
    /// lets the production head gate be exercised without a camera — matches the Kotlin/Python
    /// fixture geometry exactly, since the head-over-bar gate is sensitive to it.
    public static func pullup(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = swing(limb, sin, elbowDeg)
        let shY = swing(-limb, cos, elbowDeg)
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, -limb)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        putPair(&k, KP.leftHip, KP.rightHip, shX, shY + torso)
        k[KP.nose] = Keypoint(x: shX, y: shY - 120, score: 0.9)
        return k
    }

    /// A body mid *knee* push-up with the given elbow angle: hands and knees on the floor, shins
    /// folded up behind, and no plank line from shoulder to ankle.
    ///
    /// Deliberately identical to `pushup` everywhere the push-up path actually looks — the
    /// shoulder-elbow-wrist chain and the torso — because that is the finding this fixture exists
    /// to pin down. The knees and shins are placed honestly so the fixture describes the real
    /// movement, not so the engine can read them: nothing in the push-up path consults them.
    /// Mirrors Kotlin's `PoseFixtures.kneePushup`.
    public static func kneePushup(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = swing(limb, sin, elbowDeg)
        let shY = swing(limb, cos, elbowDeg)
        // The floor is the line the planted hands sit on.
        let floorY = limb
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, floorY)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        putPair(&k, KP.leftHip, KP.rightHip, shX - torso, shY)
        // Knees down on the floor rather than trailing the hips, and the shins raised behind.
        putPair(&k, KP.leftKnee, KP.rightKnee, shX - torso - 40, floorY)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, shX - torso - 40, floorY - 60)
        return k
    }

    /// A body mid *inverted row*: hands on a low bar overhead, body running away horizontally
    /// instead of hanging below.
    ///
    /// The arm chain is exactly `pullup`'s, because that is the point — the elbow swings the
    /// same range, the wrists sit above the hips and the head reaches the bar line. Every
    /// pull-up gate except the torso's direction is satisfied by a row. Mirrors Kotlin's
    /// `PoseFixtures.invertedRow`.
    public static func invertedRow(_ elbowDeg: Float) -> [Keypoint] {
        var k = blank()
        let shX = swing(limb, sin, elbowDeg)
        let shY = swing(-limb, cos, elbowDeg)
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, -limb)
        putPair(&k, KP.leftShoulder, KP.rightShoulder, shX, shY)
        // The body runs out sideways from the shoulders rather than hanging under them.
        putPair(&k, KP.leftHip, KP.rightHip, shX + torso, shY)
        putPair(&k, KP.leftKnee, KP.rightKnee, shX + torso + 80, shY)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, shX + torso + 160, shY)
        k[KP.nose] = Keypoint(x: shX, y: shY - 120, score: 0.9)
        return k
    }

    /// Standing on the floor holding a resistance band at chest height, arms straight.
    ///
    /// The posture that taught a bar in the wrong place on real band footage: hands above the
    /// hips with the elbows extended, so every test the bar used to be learned from passes — but
    /// the hands are below the head, because the band is held in front of the chest rather than
    /// gripped overhead. Mirrors Kotlin's `PoseFixtures.bandSetup`.
    public static func bandSetup() -> [Keypoint] {
        var k = blank()
        putPair(&k, KP.leftShoulder, KP.rightShoulder, 0, 0)
        putPair(&k, KP.leftHip, KP.rightHip, 0, torso)
        putPair(&k, KP.leftElbow, KP.rightElbow, 0, 0.2 * torso)
        putPair(&k, KP.leftWrist, KP.rightWrist, 0, 0.4 * torso)
        k[KP.nose] = Keypoint(x: 0, y: -0.4 * torso, score: 0.9)
        putPair(&k, KP.leftKnee, KP.rightKnee, 0, 2 * torso)
        putPair(&k, KP.leftAnkle, KP.rightAnkle, 0, 3 * torso)
        return k
    }

    /// Nothing confidently detected — the "step into frame" case.
    public static func empty() -> [Keypoint] { blank() }
}

/// Drives an engine the way a camera would.
public final class Rig {
    public let engine: WorkoutEngine
    public var clock: Int64 = 0

    public init(fixedExercise: Exercise? = nil, profile: CindyProfile = .standard) {
        engine = WorkoutEngine(fixedExercise: fixedExercise, profile: profile)
    }

    public func hold(_ pose: [Keypoint], frames: Int = 10) {
        for _ in 0..<frames {
            _ = engine.onFrame(pose, now: clock)
            clock += 100
        }
    }

    @discardableResult
    public func setupHold(_ pose: [Keypoint], frames: Int = 10) -> Setup {
        var last = engine.onSetupFrame(pose, now: clock)
        for _ in 0..<frames {
            last = engine.onSetupFrame(pose, now: clock)
            clock += 100
        }
        return last
    }

    public func pullup(hang: Float = 170, top: Float = 60) {
        hold(PoseFixtures.pullup(hang))
        hold(PoseFixtures.pullup(top))
    }

    /// One rep, starting and finishing in the position the movement is held in.
    ///
    /// The leading frame matters: a push-up begins at lockout and the engine will not score it
    /// until it has seen the athlete get there. Starting at the bottom instead described an
    /// athlete who materialises mid-rep, and let the climb up out of the previous movement count
    /// as the first rep of this one. Mirrors Kotlin's `doPushup()`.
    public func pushup() {
        hold(PoseFixtures.pushup(175))
        hold(PoseFixtures.pushup(80))
        hold(PoseFixtures.pushup(175))
    }

    /// Mirrors Kotlin's `doSquat()` — see `pushup()`.
    public func squat() {
        hold(PoseFixtures.squat(175))
        hold(PoseFixtures.squat(80))
        hold(PoseFixtures.squat(175))
    }
}

extension Array where Element == Keypoint {

    /// Shifts a whole body, as if the athlete stepped off the bar or along it. Unseen joints stay
    /// unseen. Mirrors the Kotlin tests' `Array<Keypoint>.moved`.
    public func moved(dx: Float, dy: Float) -> [Keypoint] {
        map { $0.score <= 0 ? $0 : Keypoint(x: $0.x + dx, y: $0.y + dy, score: $0.score) }
    }

    /// Shrinks a body about the origin, as if the athlete were much further from the camera.
    /// Mirrors the Kotlin tests' `Array<Keypoint>.scaled`.
    public func scaled(_ factor: Float) -> [Keypoint] {
        map { $0.score <= 0 ? $0 : Keypoint(x: $0.x * factor, y: $0.y * factor, score: $0.score) }
    }
}
