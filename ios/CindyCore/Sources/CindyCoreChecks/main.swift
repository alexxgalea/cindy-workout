import Foundation
import CindyCore

// ── the counter ───────────────────────────────────────────────────────────────

Check.suite("RepCounter") {
    func hold(_ c: RepCounter, _ v: Float, from t: Int64, frames: Int = 10) -> Int {
        var reps = 0
        for i in 0..<frames where c.update(v, now: t + Int64(i) * 100) { reps += 1 }
        return reps
    }

    var c = RepCounter(downBelow: 100, upAbove: 150)
    _ = hold(c, 80, from: 0)
    Check.equal(hold(c, 170, from: 1000), 1, "full travel scores one rep")

    c = RepCounter(downBelow: 100, upAbove: 150)
    _ = hold(c, 80, from: 0)
    var t: Int64 = 1000
    for v: Float in [110, 140, 120, 145, 105, 149] { _ = hold(c, v, from: t); t += 1000 }
    Check.equal(c.count, 0, "jitter inside the dead zone never scores")

    c = RepCounter(downBelow: 100, upAbove: 150)
    t = 0
    for _ in 0..<10 {
        _ = hold(c, 80, from: t); t += 1000
        _ = hold(c, 170, from: t); t += 1000
    }
    Check.equal(c.count, 10, "ten clean cycles score ten")

    c = RepCounter(downBelow: 100, upAbove: 150, minRepMs: 5000, smoothing: 1)
    _ = c.update(80, now: 0)
    _ = c.update(170, now: 100)
    _ = c.update(80, now: 200)
    _ = c.update(170, now: 300)
    Check.equal(c.count, 1, "reps faster than the debounce are rejected")

    c = RepCounter(downBelow: 100, upAbove: 150)
    _ = hold(c, 80, from: 0)
    Check.equal(c.update(.nan, now: 1000), false, "NaN samples are ignored")
    _ = hold(c, 170, from: 2000)
    Check.equal(c.count, 1, "and do not break the smoother")

    c = RepCounter(downBelow: 100, upAbove: 150)
    c.forceIncrement(); c.forceIncrement(); c.forceDecrement()
    Check.equal(c.count, 1, "minus takes a rep back")
    c.forceDecrement(); c.forceDecrement()
    Check.equal(c.count, 0, "minus stops at zero")

    c = RepCounter(downBelow: 100, upAbove: 150, minRange: 40)
    _ = hold(c, 80, from: 0)
    _ = hold(c, 170, from: 1000)
    Check.equal(c.calibrated, true, "the band calibrates from a full rep")
    c.resetBand()
    Check.equal(c.count, 1, "recalibration keeps the score")
    Check.equal(c.calibrated, false, "recalibration forgets the band")
}

// ── the Cindy progression ─────────────────────────────────────────────────────

Check.suite("WorkoutEngine") {
    var r = Rig()
    Check.equal(r.engine.exercise, .pullup, "starts on pull-ups")

    r = Rig()
    r.hold(PoseFixtures.empty(), frames: 5)
    Check.equal(r.engine.bodyVisible, false, "an empty frame is not a body")
    Check.equal(r.engine.hint, "Step into frame", "and says so")

    r = Rig()
    for _ in 0..<4 { r.pullup() }
    Check.equal(r.engine.reps, 4, "pull-ups count")
    r.pullup()
    Check.equal(r.engine.exercise, .pushup, "and hand over at five")

    r = Rig()
    for _ in 0..<5 { r.pullup() }
    for _ in 0..<10 { r.pushup() }
    for _ in 0..<15 { r.squat() }
    Check.equal(r.engine.rounds, 1, "a full round closes")
    Check.equal(r.engine.exercise, .pullup, "and restarts on pull-ups")
    Check.equal(r.engine.totalReps, 30, "thirty reps to the round")

    r = Rig()
    for _ in 0..<5 { r.pullup(hang: 150, top: 90) }
    Check.equal(r.engine.exercise, .pushup, "a pull-up from a low phone still counts")

    r = Rig()
    for _ in 0..<5 { r.pullup(hang: 175, top: 45) }
    Check.equal(r.engine.exercise, .pushup, "shoulders above the hands does not void the rep")

    r = Rig()
    for _ in 0..<5 {
        r.hold(PoseFixtures.pullup(170))
        r.hold(PoseFixtures.pullup(145))
    }
    Check.equal(r.engine.reps, 0, "barely bending the arms scores nothing")

    r = Rig()
    for _ in 0..<2 { r.pullup(hang: 170, top: 55) }
    for _ in 0..<4 { r.pullup(hang: 170, top: 120) }
    Check.equal(r.engine.reps, 2, "full reps set the standard for partial ones")

    r = Rig()
    for _ in 0..<6 { r.pushup() }
    Check.equal(r.engine.reps, 0, "push-ups do not leak into the pull-up block")
}

// ── minus and recalibration ───────────────────────────────────────────────────

Check.suite("Undo and recalibrate") {
    var r = Rig()
    for _ in 0..<3 { r.pullup() }
    Check.equal(r.engine.undoRep(), .undo, "minus reports an undo")
    Check.equal(r.engine.reps, 2, "and drops the count")

    r = Rig()
    for _ in 0..<5 { r.pullup() }
    _ = r.engine.undoRep()
    Check.equal(r.engine.exercise, .pullup, "minus steps back over a movement boundary")
    Check.equal(r.engine.reps, 4, "landing on the last rep of the previous movement")

    r = Rig()
    for _ in 0..<5 { r.pullup() }
    for _ in 0..<10 { r.pushup() }
    for _ in 0..<15 { r.squat() }
    _ = r.engine.undoRep()
    Check.equal(r.engine.rounds, 0, "minus steps back over a round boundary")
    Check.equal(r.engine.exercise, .squat, "onto the previous round's squats")
    Check.equal(r.engine.totalReps, 29, "and the total follows")

    r = Rig()
    Check.equal(r.engine.undoRep(), RepEvent.none, "minus at zero does nothing")
    Check.equal(r.engine.totalReps, 0, "and leaves the score alone")

    r = Rig()
    for _ in 0..<3 { r.pullup() }
    r.engine.recalibrate()
    Check.equal(r.engine.reps, 3, "recalibrating keeps the reps")
    Check.equal(r.engine.calibrated, false, "but forgets the band")
    for _ in 0..<2 { r.pullup() }
    Check.equal(r.engine.exercise, .pushup, "and re-learns from the next reps")
}

// ── the pre-workout check ─────────────────────────────────────────────────────

Check.suite("Setup") {
    var r = Rig()
    r.engine.beginSetup()
    var s = r.setupHold(PoseFixtures.empty(), frames: 3)
    Check.equal(s.stage, .framing, "an empty frame stays at framing")
    Check.equal(s.missing.contains("hands"), true, "and names the hands as missing")

    r = Rig()
    r.engine.beginSetup()
    s = r.setupHold(PoseFixtures.pullup(170))
    Check.equal(s.stage, .moving, "a framed body moves on to calibration")
    for _ in 0..<2 {
        _ = r.setupHold(PoseFixtures.pullup(170))
        s = r.setupHold(PoseFixtures.pullup(60))
    }
    Check.equal(s.stage, .ready, "two calibration reps get the workout going")

    r = Rig()
    r.engine.beginSetup()
    for _ in 0..<12 {
        _ = r.setupHold(PoseFixtures.pullup(170))
        s = r.setupHold(PoseFixtures.pullup(155))
    }
    Check.equal(s.stage, .poor, "a phone that cannot see the movement is called out")

    r = Rig()
    r.engine.beginSetup()
    for _ in 0..<2 {
        _ = r.setupHold(PoseFixtures.pullup(170))
        _ = r.setupHold(PoseFixtures.pullup(55))
    }
    r.engine.finishSetup()
    Check.equal(r.engine.reps, 0, "setup reps do not count toward the workout")
    Check.expect(r.engine.learnedRange > 90, "but the band they taught survives")
}

// ── records ───────────────────────────────────────────────────────────────────

Check.suite("Records") {
    Check.equal(Attempt(rounds: 27, reps: 0, atMillis: 0).scoreLabel, "27", "score reads as rounds")
    Check.equal(Attempt(rounds: 12, reps: 7, atMillis: 0).scoreLabel, "12 + 7", "and rounds plus reps")
    Check.equal(Records.benchmarkName, "Tom Holland", "the benchmark is Tom Holland")
    Check.equal(Records.benchmark.totalReps, 810, "at 27 rounds")

    let list = [
        Attempt(rounds: 3, reps: 12, atMillis: 1000, durationMs: 1_200_000,
                pausedMs: 45_000, roundSplitsMs: [60_000, 71_000, 68_000]),
        Attempt(rounds: 1, reps: 0, atMillis: 2000, durationMs: 90_000,
                pausedMs: 0, roundSplitsMs: [90_000])
    ]
    Check.equal(Records.decode(Records.encode(list)), list, "splits and pauses round-trip")

    let legacy = Records.decode("12,7,1000\n14,0,2000")
    Check.equal(legacy.count, 2, "records saved before splits existed still load")
    Check.equal(legacy[0].roundSplitsMs, [], "with no splits")

    Check.equal(Records.decode(nil).count, 0, "nil decodes to nothing")
    Check.equal(Records.decode("garbage").count, 0, "junk decodes to nothing")

    let paused = Attempt(rounds: 5, reps: 0, atMillis: 0,
                         durationMs: 1_200_000, pausedMs: 180_000)
    Check.equal(paused.realTimeMs, 1_380_000, "real time counts the pauses")
    Check.equal(paused.avgRoundMs, 240_000, "the average round does not")

    Check.equal(Records.ranked([
        Attempt(rounds: 10, reps: 0, atMillis: 0),
        Attempt(rounds: 15, reps: 0, atMillis: 0)
    ])[0].rounds, 15, "ranking puts the highest first")

    Check.equal(formatDuration(65_000), "1:05", "durations read as minutes and seconds")
    Check.equal(formatDuration(20 * 60 * 1000), "20:00", "including twenty minutes")
}

// ── levels ────────────────────────────────────────────────────────────────────

Check.suite("Levels") {
    Check.equal(Level.of(10), .intermediate, "a complete Cindy lands at intermediate")
    Check.equal(Level.of(0), .firstSteps, "the ladder starts at first steps")
    Check.equal(Level.of(5), .novice, "climbs to novice")
    Check.equal(Level.of(16), .advanced, "then advanced")
    Check.equal(Level.of(21), .elite, "then elite")
    Check.equal(Level.of(27), .legend, "then legend")
    Check.equal(Level.legend.minRounds, Records.benchmark.rounds, "legend is level with the benchmark")
    Check.equal(Level.next(after: .legend) == nil, true, "nothing above legend")
    Check.equal(Level.roundsToNext(9), 1, "one round short of intermediate")
    Check.close(Level.progress(10), 0, 0.001, "progress starts at zero in a level")
    Check.close(Level.progress(27), 1, 0.001, "and is full at the top")

    let mins = Level.allCases.map(\.minRounds)
    Check.equal(mins, mins.sorted(), "thresholds are increasing")
    Check.equal(mins.count, Set(mins).count, "and distinct")
}

// ── the bar gate ──────────────────────────────────────────────────────────────

Check.suite("Bar gate") {
    /// Shifts a whole body, as if the athlete stepped off the bar.
    func moved(_ k: [Keypoint], dx: Float, dy: Float) -> [Keypoint] {
        k.map { $0.score <= 0 ? $0 : Keypoint(x: $0.x + dx, y: $0.y + dy, score: $0.score) }
    }

    var r = Rig()
    Check.equal(r.engine.barKnown, false, "the bar is unknown until someone hangs from it")
    r.hold(PoseFixtures.pullup(170))
    Check.equal(r.engine.barKnown, true, "a dead hang marks the bar")

    r = Rig()
    r.hold(PoseFixtures.pullup(60))
    Check.equal(r.engine.barKnown, false, "a bent-armed frame alone does not mark it")

    r = Rig()
    for _ in 0..<2 { r.pullup() }
    Check.equal(r.engine.reps, 2, "honest reps at the bar count")
    for _ in 0..<6 {
        r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
        r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
    }
    Check.equal(r.engine.reps, 2, "the same arm movement off the bar scores nothing")
    Check.equal(r.engine.hint, "Get on the bar", "and says why")

    r = Rig()
    for _ in 0..<2 { r.pullup() }
    for _ in 0..<6 {
        r.hold(moved(PoseFixtures.pullup(170), dx: 500, dy: 0))
        r.hold(moved(PoseFixtures.pullup(60), dx: 500, dy: 0))
    }
    Check.equal(r.engine.reps, 2, "and nor does the same movement far to the side")

    r = Rig()
    for _ in 0..<2 { r.pullup() }
    for _ in 0..<2 {
        r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
        r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
    }
    for _ in 0..<3 { r.pullup() }
    Check.equal(r.engine.exercise, .pushup, "stepping back onto the bar resumes counting")

    r = Rig()
    for _ in 0..<2 { r.pullup() }
    for _ in 0..<3 {
        r.hold(moved(PoseFixtures.pullup(170), dx: 40, dy: 0))
        r.hold(moved(PoseFixtures.pullup(60), dx: 40, dy: 0))
    }
    Check.equal(r.engine.exercise, .pushup, "a small shift along the bar is still on the bar")

    r = Rig()
    for _ in 0..<2 { r.pullup() }
    r.engine.recalibrate()
    Check.equal(r.engine.barKnown, false, "recalibrating forgets the bar")
    for _ in 0..<3 {
        r.hold(moved(PoseFixtures.pullup(170), dx: 0, dy: 400))
        r.hold(moved(PoseFixtures.pullup(60), dx: 0, dy: 400))
    }
    Check.equal(r.engine.exercise, .pushup, "so a moved camera does not block counting")

    r = Rig()
    r.engine.beginSetup()
    for _ in 0..<2 {
        _ = r.setupHold(PoseFixtures.pullup(170))
        _ = r.setupHold(PoseFixtures.pullup(60))
    }
    Check.equal(r.engine.barKnown, true, "setup learns the bar before the workout starts")
    r.engine.finishSetup()
    Check.equal(r.engine.barKnown, true, "and it survives into the workout")
}

// ── knee push-up ──────────────────────────────────────────────────────────────
//
// Characterisation, not a spec of what ought to happen: the push-up signal is the elbow angle
// alone and the gate in front of it asks only which way the torso points, so a kneeling athlete
// already passes both. No ankle, knee or shoulder-hip-ankle line is consulted anywhere in the
// movement, so there is no strictness rule here to relax for an adaptive mode.

Check.suite("Knee push-up") {
    var r = Rig(fixedExercise: .pushup)
    r.hold(PoseFixtures.kneePushup(175))
    for _ in 0..<3 {
        r.hold(PoseFixtures.kneePushup(80))
        r.hold(PoseFixtures.kneePushup(175))
    }
    Check.equal(r.engine.reps, 3, "a knee push-up scores as a push-up: the engine has no rule it breaks")

    // Both fixtures put the same shoulder-elbow-wrist chain in front of the camera; they differ
    // only below the hips, where nothing looks.
    let strict = Rig(fixedExercise: .pushup)
    let knees = Rig(fixedExercise: .pushup)
    strict.hold(PoseFixtures.pushup(175))
    knees.hold(PoseFixtures.kneePushup(175))
    for _ in 0..<4 {
        strict.hold(PoseFixtures.pushup(80)); strict.hold(PoseFixtures.pushup(175))
        knees.hold(PoseFixtures.kneePushup(80)); knees.hold(PoseFixtures.kneePushup(175))
    }
    Check.equal(strict.engine.reps, knees.engine.reps, "the engine cannot tell a knee push-up from a standard one")
    Check.close(strict.engine.signal, knees.engine.signal, 0.01, "same elbow angle, same signal")

    // The same finding through the normal Cindy flow, where push-ups are entered from the start
    // gate that stops the walk to the floor from scoring a rep. `inStartPosition` asks only
    // `!upright`, and a kneeling plank's torso is horizontal, so the gate opens for a kneeling
    // athlete exactly as it does for a prone one.
    r = Rig()
    for _ in 0..<5 { r.pullup() }
    Check.equal(r.engine.exercise, .pushup, "hands over to push-ups at five")
    Check.equal(r.engine.awaitingStart, true, "push-ups are entered awaiting the start position")
    r.hold(PoseFixtures.kneePushup(175))
    Check.equal(r.engine.awaitingStart, false, "kneeling satisfies the start gate")
    for _ in 0..<9 {
        r.hold(PoseFixtures.kneePushup(80))
        r.hold(PoseFixtures.kneePushup(175))
    }
    Check.equal(r.engine.reps, 9, "nine knee push-ups scored")
    r.hold(PoseFixtures.kneePushup(80))
    r.hold(PoseFixtures.kneePushup(175))
    Check.equal(r.engine.exercise, .squat, "the tenth finishes the block")
}

// ── limited extension: the bar-settle fallback ─────────────────────────────────
//
// An athlete whose arms never straighten into a dead hang — limited extension, or a band taking
// enough weight — used to never establish the bar at all, since establishing it required a dead
// hang. Every frame was then refused under "Hang from the bar" and the workout scored zero
// without ever explaining why. `settleBar` locates the bar from hands simply held still overhead.

Check.suite("Limited extension (bar settle)") {
    let bottom: Float = 120  // as straight as this athlete's arms get, well under a dead hang
    let top: Float = 60

    var r = Rig(fixedExercise: .pullup)
    r.hold(PoseFixtures.pullup(bottom), frames: 20)
    Check.equal(r.engine.barKnown, false, "two seconds is not yet sustained stillness")
    r.hold(PoseFixtures.pullup(bottom), frames: 15)
    Check.equal(r.engine.barKnown, true, "a still overhead hang eventually locates the bar")

    // The fallback is a fallback: a real dead hang still establishes the bar immediately.
    r = Rig(fixedExercise: .pullup)
    r.hold(PoseFixtures.pullup(170), frames: 1)
    Check.equal(r.engine.barKnown, true, "a dead hang still locates the bar at once")

    // The case the dead-hang requirement was really guarding: a walk-up with arms overhead must
    // not teach a bar in the wrong place. Drift restarts the dwell, so it never settles.
    r = Rig(fixedExercise: .pullup)
    for step in 0..<12 {
        let shift = Float(step) * 30
        var walking = PoseFixtures.pullup(bottom)
        for i in [KP.nose, KP.leftShoulder, KP.rightShoulder, KP.leftElbow, KP.rightElbow,
                  KP.leftWrist, KP.rightWrist, KP.leftHip, KP.rightHip] {
            walking[i] = Keypoint(x: walking[i].x + shift, y: walking[i].y, score: walking[i].score)
        }
        r.hold(walking, frames: 5)
    }
    Check.equal(r.engine.barKnown, false, "a walk-up never settles, so it teaches nothing")

    // The standard, unchanged: full range of motion but never a straight arm is not a strict
    // pull-up, and the bar being findable does not relax that.
    r = Rig(fixedExercise: .pullup)
    r.hold(PoseFixtures.pullup(bottom), frames: 35)
    Check.equal(r.engine.barKnown, true, "the bar is known, so the refusal below is the gate, not the geometry")
    for _ in 0..<5 {
        r.hold(PoseFixtures.pullup(top), frames: 8)
        r.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    Check.equal(r.engine.reps, 0, "strict mode still refuses to score an athlete who never dead hangs")
}

// ── the band-assisted pull-up ───────────────────────────────────────────────────
//
// A relaxed bottom, and nothing else relaxed: the head still has to clear the bar, the hands
// still have to be on it, and RepCounter still wants the athlete's whole learned travel.

Check.suite("Assisted pull-up") {
    let bottom: Float = 120
    let top: Float = 60

    func engineFor(_ pull: PullVariant) -> Rig {
        Rig(fixedExercise: .pullup, profile: CindyProfile(pull: pull))
    }

    var r = engineFor(.bandAssistedPullUp)
    r.hold(PoseFixtures.pullup(bottom), frames: 35)
    for _ in 0..<6 {
        r.hold(PoseFixtures.pullup(top), frames: 8)
        r.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    // The first cycle teaches the counter the athlete's range; the rest score.
    Check.equal(r.engine.reps, 5, "a band-assisted pull-up counts without a dead hang")

    // The same movement, in the mode that says it is a strict pull-up. Unchanged.
    r = engineFor(.strictPullUp)
    r.hold(PoseFixtures.pullup(bottom), frames: 35)
    for _ in 0..<6 {
        r.hold(PoseFixtures.pullup(top), frames: 8)
        r.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    Check.equal(r.engine.reps, 0, "the same reps score nothing in strict mode")

    // The gate that is not relaxed: pulling only partway is not a rep in either mode.
    r = engineFor(.bandAssistedPullUp)
    r.hold(PoseFixtures.pullup(bottom), frames: 35)
    for _ in 0..<6 {
        r.hold(PoseFixtures.pullup(95), frames: 8)
        r.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    Check.equal(r.engine.reps, 0, "a band-assisted pull-up still requires the head over the bar")

    // And the bar itself is still a gate: arms overhead a long way from where the bar was
    // learned do not score, assisted or not.
    r = engineFor(.bandAssistedPullUp)
    r.hold(PoseFixtures.pullup(bottom), frames: 35)
    let before = r.engine.reps
    for _ in 0..<6 {
        for angle in [top, bottom] {
            var offBar = PoseFixtures.pullup(angle)
            for i in offBar.indices where offBar[i].score > 0 {
                offBar[i] = Keypoint(x: offBar[i].x + 900, y: offBar[i].y, score: offBar[i].score)
            }
            r.hold(offBar, frames: 8)
        }
    }
    Check.equal(r.engine.reps, before, "overhead movement away from the bar does not count")

    // An inverted row satisfies every pull-up gate but one: the wrists are above the hips, the
    // bar can be learned from the hands, the head reaches the bar line and the elbow swings a
    // full range. Only the torso's direction separates the families.
    for variant in [PullVariant.strictPullUp, .bandAssistedPullUp] {
        let rows = engineFor(variant)
        rows.hold(PoseFixtures.pullup(bottom), frames: 35)
        for _ in 0..<6 {
            rows.hold(PoseFixtures.invertedRow(top), frames: 8)
            rows.hold(PoseFixtures.invertedRow(bottom), frames: 8)
        }
        Check.equal(rows.engine.reps, 0, "inverted rows never count as \(variant.label)")
    }
    let rowBar = engineFor(.strictPullUp)
    for _ in 0..<6 {
        rowBar.hold(PoseFixtures.invertedRow(top), frames: 8)
        rowBar.hold(PoseFixtures.invertedRow(bottom), frames: 8)
    }
    Check.equal(rowBar.engine.barKnown, false, "and an inverted row teaches no bar")

    // The gate is on orientation, not stillness: a wobble mid-rep is absorbed by the same
    // dropout window that already rides out an occlusion.
    let wobble = engineFor(.bandAssistedPullUp)
    wobble.hold(PoseFixtures.pullup(bottom), frames: 35)
    for _ in 0..<2 {
        wobble.hold(PoseFixtures.pullup(top), frames: 8)
        wobble.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    let beforeWobble = wobble.engine.reps
    wobble.hold(PoseFixtures.pullup(bottom), frames: 8)
    wobble.hold(PoseFixtures.invertedRow(bottom), frames: 4)
    wobble.hold(PoseFixtures.pullup(top), frames: 8)
    Check.equal(wobble.engine.reps, beforeWobble + 1, "a brief wobble does not throw away a rep")

    // Setting the band up must not teach a bar. Found on real footage: standing holding the
    // band at chest height satisfies every other condition the bar was learned from, so the bar
    // was fixed at the athlete's chest and every real rep afterwards was refused with "Get on
    // the bar" with no way back, since refinement requires already passing the gate.
    let bandSetup = engineFor(.bandAssistedPullUp)
    bandSetup.hold(PoseFixtures.bandSetup(), frames: 60)
    Check.equal(bandSetup.engine.barKnown, false, "holding a band at chest height teaches no bar")
    bandSetup.hold(PoseFixtures.pullup(bottom), frames: 35)
    Check.equal(bandSetup.engine.barKnown, true, "the real hang afterwards still finds it")
    for _ in 0..<6 {
        bandSetup.hold(PoseFixtures.pullup(top), frames: 8)
        bandSetup.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    Check.equal(bandSetup.engine.reps, 5, "and the reps score normally after it")

    // Rep provenance: a tapped rep counts, and is remembered as tapped.
    let manual = engineFor(.footAssistedPullUp)
    manual.engine.manualRep()
    Check.equal(manual.engine.reps, 1, "a manual rep is recorded: reps")
    Check.equal(manual.engine.manualReps, 1, "a manual rep is recorded: manualReps")
    Check.equal(manual.engine.lastRepSource == .manual, true, "a manual rep is recorded: source")

    let undoRig = engineFor(.footAssistedPullUp)
    undoRig.engine.manualRep()
    undoRig.engine.manualRep()
    _ = undoRig.engine.undoRep()
    Check.equal(undoRig.engine.reps, 1, "undoing a tapped rep takes the rep back")
    Check.equal(undoRig.engine.manualReps, 1, "and takes the tap back too")

    let camera = engineFor(.bandAssistedPullUp)
    camera.hold(PoseFixtures.pullup(bottom), frames: 35)
    for _ in 0..<3 {
        camera.hold(PoseFixtures.pullup(top), frames: 8)
        camera.hold(PoseFixtures.pullup(bottom), frames: 8)
    }
    Check.expect(camera.engine.reps > 0, "the camera scored at least one")
    Check.equal(camera.engine.manualReps, 0, "a rep the camera scored is not counted as manual")
    Check.equal(camera.engine.lastRepSource == .auto, true, "and the source says so")
}

// ── movement profiles: honest history ────────────────────────────────────────
//
// An adapted session is recorded as what it was, and ranked against its own kind: never quietly
// filed as strict, never taking the strict record, never earning a rung on a ladder calibrated
// against a workout it did not attempt — while still counting as a session the athlete did.

Check.suite("Variations") {
    let adaptive = CindyProfile(pull: .bandAssistedPullUp, push: .kneePushUp, squat: .boxSquat)
    func attempt(_ rounds: Int, reps: Int = 0, at: Int64 = 1000, profile: CindyProfile? = .standard,
                manualReps: Int = 0) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: at, durationMs: 20 * 60 * 1000,
               profile: profile, manualReps: manualReps)
    }

    // The profile survives a round trip, and reps tapped in survive with it.
    let saved = Records.decode(Records.encode([attempt(7, reps: 12, profile: adaptive, manualReps: 4)]))
    Check.equal(saved.count, 1, "one attempt round-trips")
    Check.equal(saved.first?.profile, adaptive, "an adaptive session stores the movements it was run with")
    Check.equal(saved.first?.manualReps, 4, "reps tapped in survive a round trip")

    // History written before the choice existed was standard Cindy, because that was the only
    // thing the app did.
    let v3 = Records.decode("v3|8|12|1700000000000|1200000|0|150000,160000").first
    Check.equal(v3?.profile, CindyProfile.standard, "attempts written before variations existed read as standard")
    Check.equal(v3?.rounds, 8, "and the rounds are unaffected")

    // The one case where guessing would be a lie: a movement this build does not know cannot be
    // filed under one it does, or an assisted session would silently promote into the strict
    // record.
    let unknown = Records.decode("v4|8|0|1700000000000|1200000|0||ONE_ARM_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0").first
    Check.equal(unknown?.profile == nil, true, "an unrecognised movement leaves the profile unknown")
    Check.equal(unknown?.rounds, 8, "but the session itself is still theirs")

    // Separate records, and not merely "standard versus the rest": two different adaptations are
    // no more comparable to each other than either is to the strict movement.
    let history = [
        attempt(8, at: 1, profile: .standard),
        attempt(20, at: 2, profile: adaptive)
    ]
    Check.equal(Records.bestIn(history, profile: .standard)?.rounds, 8, "the strict record is untouched")
    Check.equal(Records.bestIn(history, profile: adaptive)?.rounds, 20, "an adaptive result never becomes it")

    let knees = CindyProfile(push: .kneePushUp)
    let box = CindyProfile(squat: .boxSquat)
    let twoAdaptations = [attempt(9, at: 1, profile: knees), attempt(14, at: 2, profile: box)]
    Check.equal(Records.bestIn(twoAdaptations, profile: knees)?.rounds, 9, "each adaptation keeps its own record")
    Check.equal(Records.bestIn(twoAdaptations, profile: box)?.rounds, 14, "the other adaptation does not share it")
    Check.equal(Records.bestIn(twoAdaptations, profile: .standard) == nil, true, "and neither is the strict record")

    // The strict ladder and the benchmark do not rank a session they do not describe.
    Check.equal(attempt(12).level, .intermediate, "a standard session gets a rung")
    Check.equal(attempt(12, profile: adaptive).level == nil, true, "an adaptive session gets no rung")
    Check.equal(attempt(12).caption, "Intermediate", "a standard caption is the rung")
    Check.equal(
        attempt(28, profile: adaptive).caption,
        "Adaptive Cindy · band-assisted pull-ups · knee push-ups · box squats",
        "an adaptive caption names what changed instead"
    )
    Check.equal(Records.beatsBenchmark(attempt(28)), true, "a strict score can pass the benchmark")
    Check.equal(Records.beatsBenchmark(attempt(28, profile: adaptive)), false,
               "an adaptive session never does, however many rounds")

    // The picker's own memory: a preference, not a record, so an unknown choice can safely fall
    // back to standard rather than staying unknown.
    Check.equal(Variations.decode(Variations.encode(adaptive)), adaptive, "the chosen profile round-trips")
    Check.equal(Variations.decode(nil), CindyProfile.standard, "no saved choice is the standard movement")
    let partlyUnknown = Variations.decode("ONE_ARM_PULL_UP|KNEE_PUSH_UP|AIR_SQUAT")
    Check.equal(partlyUnknown.pull, .strictPullUp, "an unknown saved choice falls back to standard")
    Check.equal(partlyUnknown.push, .kneePushUp, "but the choices it does understand are kept")

    // Labels name only what changed.
    Check.equal(CindyProfile.standard.label(), "Cindy", "a standard profile is just Cindy")
    Check.equal(CindyProfile(push: .kneePushUp).label(), "Adaptive Cindy · knee push-ups",
               "an adaptive one names only the change")
    Check.equal(CindyProfile.standard.fullyAutomatic, true, "the standard profile is fully automatic")
    Check.equal(adaptive.fullyAutomatic, true, "so is this adaptive one -- all three variants are AUTO-tracked")
    Check.equal(CindyProfile(pull: .negativePullUp).manualMovements, [.pullup],
               "a profile knows which movements it will ask to be tapped in")
}

Check.finish()
