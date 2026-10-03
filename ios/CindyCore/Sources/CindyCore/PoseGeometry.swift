import Foundation

/// Pure pose-geometry reads shared by `WorkoutEngine` and, from Phase 2, `AthleteLock`.
///
/// Everything here is a stateless function of a keypoint array (and, where the answer depends on
/// it, the `Exercise` in question): no learned thresholds, no hold counters, nothing that depends
/// on frames seen before this one. `WorkoutEngine` keeps every stateful gate — the learned bar, a
/// hold counter such as `overheadHoldFrames`, the calibrated band — itself, and calls in here only
/// for the geometry underneath them.
enum PoseGeometry {
    /// MoveNet/Vision confidence below which a keypoint is treated as unseen.
    private static let minScore: Float = 0.30

    /// How far the shoulders must sit above the hips, in torso lengths, to call the athlete
    /// upright.
    ///
    /// A plank and a standing body both have straight legs, so the knee angle cannot tell them
    /// apart — only the direction the torso is pointing can. A vertical torso scores 1.0 and a
    /// horizontal one 0.0; the threshold leaves room for the forward lean of a real squat and for
    /// a phone standing on the floor looking up.
    private static let uprightTorsos: Float = 0.7

    /// How far the knees must sit below the hips, in torso lengths, to call the athlete stood up
    /// rather than gathered in a crouch.
    ///
    /// A vertical torso is not standing. People get up off the floor by bringing the torso
    /// upright first and collecting themselves on their haunches, which reads as upright for most
    /// of a second — long enough to open a gate waiting only for that, after which the drive out
    /// of the crouch scored as a rep. Standing carries the hips a whole thigh above the knees; a
    /// crouch puts them level with, or below, them.
    ///
    /// An offset rather than a knee angle, on purpose: an angle threshold is what locked out the
    /// athlete whose foreshortened full extension only read 145 degrees.
    private static let standingTorsos: Float = 0.5

    static func ok(_ p: Keypoint) -> Bool { p.score >= minScore }

    /// Kotlin's `hypot(Float, Float)`: worked out in `Double` and rounded to `Float` once.
    ///
    /// `hypotf` is correctly rounded in `Float`, which is not the same thing: the two can differ
    /// in the last bit, and the engine's thresholds are exact comparisons.
    static func hypot32(_ x: Float, _ y: Float) -> Float {
        Float(hypot(Double(x), Double(y)))
    }

    static func midpoint(_ k: [Keypoint], _ a: Int, _ b: Int) -> Keypoint? {
        let pa = k[a], pb = k[b]
        if ok(pa) && ok(pb) {
            return Keypoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2, score: min(pa.score, pb.score))
        }
        if ok(pa) { return pa }
        if ok(pb) { return pb }
        return nil
    }

    static func torsoLength(_ k: [Keypoint]) -> Float? {
        guard let sh = midpoint(k, KP.leftShoulder, KP.rightShoulder),
              let hip = midpoint(k, KP.leftHip, KP.rightHip) else { return nil }
        return hypot32(sh.x - hip.x, sh.y - hip.y)
    }

    /// Averages the same joint angle on both sides, using whichever sides are confidently seen.
    static func bilateralAngle(_ k: [Keypoint],
                                _ la: Int, _ lb: Int, _ lc: Int,
                                _ ra: Int, _ rb: Int, _ rc: Int) -> Float {
        let l = angle(k[la], k[lb], k[lc])
        let r = angle(k[ra], k[rb], k[rc])
        if !l.isNaN && !r.isNaN { return (l + r) / 2 }
        if !l.isNaN { return l }
        if !r.isNaN { return r }
        return .nan
    }

    /// Interior angle at `b`, in degrees, or NaN if any vertex is not confidently seen.
    static func angle(_ a: Keypoint, _ b: Keypoint, _ c: Keypoint) -> Float {
        guard ok(a), ok(b), ok(c) else { return .nan }
        let abx = a.x - b.x, aby = a.y - b.y
        let cbx = c.x - b.x, cby = c.y - b.y
        let mag = hypot32(abx, aby) * hypot32(cbx, cby)
        guard mag >= 1e-4 else { return .nan }
        let cosine = max(-1, min(1, (abx * cbx + aby * cby) / mag))
        // Kotlin: Math.toDegrees(acos(cos).toDouble()).toFloat(). `acos` of a Float is worked out in
        // Double and rounded to Float, which is then widened and scaled by Java's constant.
        let radians = Float(acos(Double(cosine)))
        return Float(Double(radians) * 57.29577951308232)
    }

    /// True when the shoulders sit well above the hips: torso vertical, not lying down.
    static func upright(_ k: [Keypoint]) -> Bool {
        guard let sh = midpoint(k, KP.leftShoulder, KP.rightShoulder),
              let hp = midpoint(k, KP.leftHip, KP.rightHip) else { return false }
        let torso = hypot32(sh.x - hp.x, sh.y - hp.y)
        guard torso >= 1 else { return false }
        return (hp.y - sh.y) >= uprightTorsos * torso
    }

    /// Upright *and* stood up on the legs, rather than folded over them in a crouch.
    static func standing(_ k: [Keypoint]) -> Bool {
        guard upright(k),
              let hp = midpoint(k, KP.leftHip, KP.rightHip),
              let kn = midpoint(k, KP.leftKnee, KP.rightKnee),
              let torso = torsoLength(k) else { return false }
        return (kn.y - hp.y) >= standingTorsos * torso
    }

    /// Hands overhead, tested against the hips rather than the shoulders.
    ///
    /// The shoulders climb past the hands at the top of a good rep, so gating on them rejects the
    /// peak of the movement. The hips stay well below the hands throughout, which separates
    /// hanging from a push-up without discarding the reps worth counting.
    static func hangingFromBar(_ k: [Keypoint]) -> Bool {
        guard let hip = midpoint(k, KP.leftHip, KP.rightHip),
              let wrist = midpoint(k, KP.leftWrist, KP.rightWrist) else { return false }
        return wrist.y < hip.y
    }

    /// Whether the hands are above the head, which is what separates hanging from a grip that
    /// merely happens to sit above the hips.
    ///
    /// At a dead hang the arms are overhead by definition, so the hands are clearly above the
    /// nose; holding a band in front of the chest puts them clearly below it. Only used to decide
    /// whether an *unknown* bar may be learned — once a bar exists, `BarZone.holds` already
    /// constrains what may refine it.
    ///
    /// A head that cannot be seen does not block anything, so the rear-view and occluded footage
    /// that already counts keeps working: this rejects one specific wrong posture, not an
    /// unclear view of the face.
    static func handsOverhead(_ k: [Keypoint], hands: Keypoint) -> Bool {
        let nose = k[KP.nose]
        return !ok(nose) || hands.y < nose.y
    }

    /// Joints the given movement cannot be judged without, named for a human.
    static func missingJoints(_ k: [Keypoint], _ exercise: Exercise) -> [String] {
        let needed: [(String, (Int, Int))]
        switch exercise {
        case .pullup, .pushup:
            needed = [
                ("shoulders", (KP.leftShoulder, KP.rightShoulder)),
                ("elbows", (KP.leftElbow, KP.rightElbow)),
                ("hands", (KP.leftWrist, KP.rightWrist)),
                ("hips", (KP.leftHip, KP.rightHip))
            ]
        case .squat:
            needed = [
                ("shoulders", (KP.leftShoulder, KP.rightShoulder)),
                ("hips", (KP.leftHip, KP.rightHip)),
                ("knees", (KP.leftKnee, KP.rightKnee)),
                ("ankles", (KP.leftAnkle, KP.rightAnkle))
            ]
        }
        // midpoint accepts either side, so a joint counts as seen if one of the pair is.
        return needed.filter { midpoint(k, $0.1.0, $0.1.1) == nil }.map { $0.0 }
    }
}
