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

Check.finish()
