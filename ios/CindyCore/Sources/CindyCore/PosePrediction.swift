import Foundation

/// Where to draw each joint *now*, given poses that were computed some time ago.
///
/// ### Why draw anything other than the last pose
///
/// The skeleton is an honest report of a frame that has already happened. Between the camera and
/// the screen sit a conversion, a crop and a model, and the athlete has kept moving through all of
/// it — so a faithful drawing of the last completed pose is, by construction, a drawing of where
/// the body was, not where it is.
///
/// Carrying each joint forward along the velocity it was last seen moving at trades that lag for a
/// different error: the skeleton is now a guess, and a guess can be wrong in a way a late-but-true
/// drawing never is. The whole design here is about bounding that wrongness.
///
/// ### The three bounds, and the one that matters
///
/// 1. **Three poses, and a joint confident in all of them.** Two poses give a velocity but no way
///    to see a direction change. A joint that has just appeared has no history to carry.
///
/// 2. **A reversal stops it dead.** If a joint's last two velocities disagree in sign on an axis,
///    it is turning around, and prediction on that axis drops to zero for the frame.
///
///    This is the bound that earns the feature. The top of a pull-up is a hard direction reversal,
///    and it is the exact instant the athlete is looking at the screen to see whether the rep
///    counted — the worst possible moment to draw them somewhere they are not. Sign agreement
///    rather than a magnitude test on purpose: at the frame rates this runs at, velocity
///    *magnitudes* off noisy keypoints are far less trustworthy than their *direction*.
///
/// 3. **A hard cap on the shift**, as a share of the body's own size on screen, so one mis-tracked
///    frame cannot fling a wrist across the picture.
///
/// Display only. The counting engine never sees these numbers — it scores the true keypoints, and
/// nothing here touches the parity check.
public enum PosePrediction {

    /// Furthest ahead of the *capture* a joint may ever be drawn.
    ///
    /// Sized against the measured pipeline: ~190-212ms from sensor to published pose on the test
    /// handset. A cap below that cannot close the gap it exists to close, which is precisely the
    /// mistake the first version made.
    public static let maxAheadMs: Float = 250
    /// Gaps longer than this are a stall, not a frame interval; a velocity from one is fiction.
    public static let maxGapMs: Float = 500
    /// Ceiling on a predicted shift, as a share of the body's larger dimension.
    public static let maxShiftShare: Float = 0.15
    /// Below this a keypoint is treated as unseen, matching the overlay and the engine.
    public static let minScore: Float = 0.30

    /// Fills `out` — `KP.count * 2` floats, x then y per joint — with frame-pixel positions.
    ///
    /// Passing nil for `previous` or `oldest` means "no prediction", which is how the caller
    /// switches the feature off and what happens for the first two frames of every workout.
    public static func resolve(
        newest: [Keypoint],
        newestNanos: Int64,
        previous: [Keypoint]?,
        previousNanos: Int64,
        oldest: [Keypoint]?,
        oldestNanos: Int64,
        nowNanos: Int64,
        pipelineAgeMs: Float,
        out: inout [Float]
    ) {
        for i in 0..<KP.count {
            out[i * 2] = newest[i].x
            out[i * 2 + 1] = newest[i].y
        }
        guard let previous, let oldest else { return }

        let recentGap = Float(newestNanos - previousNanos) / 1_000_000
        let earlierGap = Float(previousNanos - oldestNanos) / 1_000_000
        if recentGap <= 0 || earlierGap <= 0 { return }
        if recentGap > maxGapMs || earlierGap > maxGapMs { return }

        // THE HORIZON IS MEASURED FROM CAPTURE, NOT FROM PUBLICATION.
        //
        // Poses are stamped when they are published — after the conversion, the crop and the model
        // — and those stamps are the correct basis for VELOCITY, because only the intervals between
        // them matter and those intervals track the intervals between captures.
        //
        // They are the wrong basis for the HORIZON. A pose published now describes where the body
        // was when the shutter opened, which on the measured handset is 190-212ms ago. Extrapolating
        // from the publish stamp corrected for the gap between redraws — tens of milliseconds — and
        // left the entire pipeline lag untouched.
        let ahead = min(Float(nowNanos - newestNanos) / 1_000_000 + pipelineAgeMs, maxAheadMs)
        if ahead <= 0 { return }

        let limit = bodySpan(newest) * maxShiftShare
        if limit <= 0 { return }

        for i in 0..<KP.count {
            let a = oldest[i]
            let b = previous[i]
            let c = newest[i]
            if a.score < minScore || b.score < minScore || c.score < minScore { continue }

            out[i * 2] += shift((b.x - a.x) / earlierGap, (c.x - b.x) / recentGap, aheadMs: ahead, limit: limit)
            out[i * 2 + 1] += shift((b.y - a.y) / earlierGap, (c.y - b.y) / recentGap, aheadMs: ahead, limit: limit)
        }
    }

    /// One axis of one joint: carry it forward unless it is turning around, and never far.
    ///
    /// Two guards, in order of how much they are trusted:
    ///
    /// **Sign, not magnitude.** A joint that was rising and is now falling gets nothing, and so
    /// does one that was still — a velocity of exactly zero agrees with no direction, which is the
    /// conservative reading and the one that cannot invent movement.
    ///
    /// **Then a deceleration ramp.** A hard cut at the reversal leaves a visible snap: mid-stroke
    /// the skeleton sits on the body, and the frame the direction flips it drops back by the whole
    /// prediction. Scaling by how much the joint has slowed removes the step, because a joint
    /// approaching the top of a rep is decelerating for several frames before it actually turns —
    /// the prediction fades out before it would have to be cut off.
    ///
    /// This uses velocity magnitude, which the sign rule above deliberately does not trust. It is
    /// allowed here because it is clamped to 1: a noisy magnitude can only ever make this *more*
    /// conservative than plain constant velocity, never less.
    public static func shift(_ earlier: Float, _ recent: Float, aheadMs: Float, limit: Float) -> Float {
        if signum(earlier) != signum(recent) { return 0 }
        if abs(earlier) < 1e-6 { return 0 }
        let damp = min(1, abs(recent) / abs(earlier))
        let moved = recent * damp * aheadMs
        return abs(moved) > limit ? limit * signum(moved) : moved
    }

    /// The body's larger dimension in frame pixels, which is what a shift is judged against.
    public static func bodySpan(_ k: [Keypoint]) -> Float {
        var left = Float.greatestFiniteMagnitude
        var top = Float.greatestFiniteMagnitude
        var right = -Float.greatestFiniteMagnitude
        var bottom = -Float.greatestFiniteMagnitude
        var seen = 0
        for p in k where p.score >= minScore {
            left = min(left, p.x); right = max(right, p.x)
            top = min(top, p.y); bottom = max(bottom, p.y)
            seen += 1
        }
        if seen < 2 { return 0 }
        return max(right - left, bottom - top)
    }

    /// Kotlin's `sign`: -1, 0 or 1, and NaN for NaN, so a NaN velocity agrees with nothing.
    private static func signum(_ x: Float) -> Float {
        x.isNaN ? .nan : (x > 0 ? 1 : (x < 0 ? -1 : 0))
    }
}
