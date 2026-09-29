package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.hypot

/** One round of Cindy: 5 pull-ups, 10 push-ups, 15 air squats. */
enum class Exercise(
    val label: String,
    val spoken: String,
    val target: Int,
    /**
     * True when the movement is entered from a posture the athlete has to assume first.
     *
     * Getting up off the floor after a set of push-ups traces the second half of a squat
     * exactly: a deep knee bend followed by a climb to full extension. Nothing in the knee
     * angle alone separates that from a rep, so these movements refuse to score until the
     * athlete has been seen in the position the movement actually starts from.
     *
     * Pull-ups are excluded because their own bar and dead-hang gates already do this.
     */
    val startsFromPosition: Boolean,
    /** Said and shown while that starting position has not been reached. */
    val startCue: String
) {
    PULLUP("PULL-UPS", "pull ups", 5, startsFromPosition = false, startCue = "Hang from the bar"),
    PUSHUP("PUSH-UPS", "push ups", 10, startsFromPosition = true, startCue = "Get set on the floor"),
    SQUAT("SQUATS", "squats", 15, startsFromPosition = true, startCue = "Stand up to start");

    fun next(): Exercise = entries[(ordinal + 1) % entries.size]

    fun previous(): Exercise = entries[(ordinal + entries.size - 1) % entries.size]
}

/** What the last analysed frame produced. */
enum class RepEvent { NONE, REP, UNDO, EXERCISE_DONE, ROUND_DONE }

/** How the pre-workout check is getting on. */
enum class SetupStage {
    /** Joints this movement needs are not all in shot. */
    FRAMING,
    /** Framing is good; waiting for calibration reps. */
    MOVING,
    /** Calibrated — the workout can start. */
    READY,
    /** Framing is good but the movement barely registers, so the phone is badly placed. */
    POOR
}

/** A frame's worth of pre-workout check. */
data class Setup(
    val stage: SetupStage,
    val missing: List<String>,
    val reps: Int,
    val range: Float,
    val needed: Float
)

/**
 * The gate decisions behind the most recently analysed frame.
 *
 * This is deliberately public and framework-free: the offline video harness writes it to its
 * reports, making a rejected frame explainable without duplicating any counter decisions.
 */
data class FrameDiagnostics(
    val minimumConfidence: Float = 0f,
    /** True only when the keypoints used to construct the current exercise signal are usable. */
    val scoringConfidenceAdequate: Boolean = false,
    /**
     * True when *every* joint the current movement scores from was confidently seen.
     *
     * Stricter than [scoringConfidenceAdequate] on purpose. That flag asks whether this frame
     * could be scored, and the geometry helpers behind it fall back to whichever side of the
     * body is visible, so it stays true through the single-sided view that precedes a real
     * failure. This asks the blunter question — how well can the camera read the athlete at all
     * — so that it degrades *before* counting does. TrackingHealthMonitor is the only consumer,
     * and an early warning is worthless if it arrives with the miscount.
     */
    val poseLegible: Boolean = false,
    val identityStable: Boolean = false,
    val barGateOpen: Boolean = false,
    val headAboveBar: Boolean = false,
    val deadHangSinceLastRep: Boolean = false,
    val resetBelowBarSeen: Boolean = false,
    val rejectionReason: String? = null
)

/**
 * Turns a stream of keypoints into a Cindy scorecard.
 *
 * Only the signal for the *current* exercise is evaluated. That is deliberate: the three
 * movements share joints, and scoring all of them at once lets a push-up lockout leak into
 * the squat counter.
 */
class WorkoutEngine(
    /**
     * Keeps the engine on one movement for a labelled exercise clip. The application uses the
     * default Cindy progression; the regression harness uses this mode so a ten-rep push-up
     * video is not truncated at Cindy's five-pull-up transition.
     */
    private val fixedExercise: Exercise? = null,
    /**
     * The movements this session is counting, fixed before the clock starts.
     *
     * Immutable for the life of the engine on purpose: a rep's meaning cannot be allowed to
     * change halfway through the score it contributes to. Changing movements means a new
     * session, which is also the only way the history line can stay true.
     */
    val profile: CindyProfile = CindyProfile.STANDARD
) {

    private companion object {
        /** Reps to watch before trusting the learned band. */
        const val CALIBRATION_REPS = 2
        /** How long to wait for a believable range before calling the setup bad. */
        const val POOR_AFTER_MS = 20_000L
        /** Elbow angle at or above which the arms count as straight, i.e. a dead hang. */
        const val DEAD_HANG_DEGREES = 150f
        /**
         * How far below the straightest arms yet seen still reads as a dead hang.
         *
         * 150 degrees assumes the camera sees the elbow square on. A phone on the floor looks up
         * at the athlete and foreshortens the upper arm, so a genuinely locked-out hang can
         * project as 140 — and a fixed threshold then refuses to arm a single rep for the whole
         * workout. This is the same argument that made RepCounter learn its band instead of
         * trusting fixed thresholds, applied to the gate in front of it.
         */
        const val DEAD_HANG_SLACK_DEGREES = 15f
        /**
         * Floor under the derived dead-hang angle.
         *
         * Without it the derivation eats itself: an athlete who has only ever been seen with
         * bent arms teaches a small "extension", which drops the threshold far enough that the
         * bent arms then qualify as a hang. No camera angle turns a 60-degree elbow into a
         * locked-out one, so the relaxation stops here.
         */
        const val DEAD_HANG_FLOOR_DEGREES = 130f
        /**
         * Body-scale change past which a learned bar is describing a geometry that has gone.
         *
         * The bar's tolerances are multiples of torso length, so an estimate learned while the
         * athlete stood close to the camera does not fit them hanging further away.
         */
        const val BAR_SCALE_CHANGE = 1.6f
        /** Straight-armed hangs rejected at that different scale before the bar is abandoned. */
        const val MAX_BAR_CONTRADICTIONS = 30
        /**
         * How long hands must hang overhead without moving before their position is taken as
         * the bar, when no dead hang has managed to establish one.
         *
         * Long, on purpose. This is the slow fallback behind the dead-hang route, and stillness
         * is weaker evidence than a straight-armed hang, so it has to be sustained stillness.
         */
        const val BAR_SETTLE_MS = 3_000L
        /** How far the hands may drift, in torso lengths, and still count as held still. */
        const val BAR_SETTLE_DRIFT_TORSOS = 0.2f
        /** How far below the bar the head must return before another pull-up can arm. */
        const val HEAD_RESET_TORSOS = 0.25f
        /**
         * Consecutive overhead frames before a bar may be learned *on the strength of a nose that
         * could not be seen*.
         *
         * [PoseGeometry.handsOverhead] answers true when the nose is not confidently seen, deliberately, so
         * that rear-view and occluded footage is not locked out. But that turns a missing keypoint
         * into permission, and a single dropped nose frame was enough to open the one gate
         * standing between a band held at chest height and a bar learned there. Measured on the
         * band fixture at one light level: the nose fell below confidence on exactly one frame in
         * sixty, a false bar was taught at y=458 instead of the real one at y=235, and because
         * refinement requires already passing the gate it could never recover — 401 of 532 frames
         * refused and the whole clip scored zero.
         *
         * So only the inferred case waits. A hang with the nose visible below the hands is real
         * evidence and still establishes the bar on the first frame; a rear view has to hold the
         * posture for a fifth of a second, which a genuine hang does without trying. The same
         * "a dwell, not a frame" argument [BAR_SETTLE_MS] and [START_POSITION_MS] already make,
         * applied only where the evidence is absent rather than present.
         */
        const val OVERHEAD_HOLD_FRAMES = 5
        /**
         * Unusable frames tolerated mid-rep before the cycle is abandoned.
         *
         * A pull-up occludes its own keypoints exactly where it matters: at the top the head
         * tilts back and the wrists disappear behind it. Treating the first sub-threshold frame
         * as "left the bar" threw the rep away at the moment it was earned. Eight frames is a
         * third of a second at 24fps — long enough to ride out an occlusion or a motion-blurred
         * frame, far too short to cover someone actually dropping off the bar.
         */
        const val MAX_DROPOUT_FRAMES = 8
        /**
         * How long the starting posture must hold, without extending further, to be taken up.
         *
         * Half a second of *stillness*, not half a second of merely being upright. Upright alone
         * was not enough: people get up off the floor by bringing the torso vertical first and
         * gathering themselves in a crouch, which is upright for far longer than this — and the
         * drive out of that crouch was then booked as a rep, which is the bug this exists for.
         */
        const val START_POSITION_MS = 500L
        /**
         * Further extension than this, within the dwell, means they are still getting up.
         *
         * Deliberately a *change* and not a threshold. An absolute "legs straight" angle is the
         * trap this engine keeps falling into — a phone on the floor foreshortens a standing
         * body until full extension reads 145 degrees, under the 158 needed to score, and the
         * athlete is locked out. How far a joint still has left to travel does not care where
         * the camera is standing.
         */
        const val START_SETTLE_DEGREES = 3f
        /** Smoothing on the settling signal, so raw jitter does not read as still rising. */
        const val START_SETTLE_SMOOTHING = 0.4f
    }

    private val counters = mapOf(
        // All three signals are joint angles in degrees. The pull-up one is negated because a
        // dead hang is the *extended* end of its range, the opposite way round to the others.
        // minRange is the projected travel below which a swing is not believed to be a rep at
        // all; above it the counter calibrates to the athlete and the fixed numbers stop mattering.
        Exercise.PULLUP to RepCounter(-140f, -100f, minRepMs = 400L, minRange = 40f),
        Exercise.PUSHUP to RepCounter(100f, 150f, minRepMs = 350L, minRange = 45f),
        Exercise.SQUAT to RepCounter(100f, 158f, minRepMs = 350L, minRange = 55f)
    )

    var exercise = fixedExercise ?: Exercise.PULLUP
        private set
    var rounds = 0
        private set
    /** Human-readable reason the current frame did or did not score. */
    var hint = "Step into frame"
        private set
    var bodyVisible = false
        private set

    /**
     * Reps tapped in rather than seen, across the whole session.
     *
     * Reported with the score because "87 reps" and "87 reps, 12 by hand" are different claims.
     */
    var manualReps = 0
        private set

    /** How the most recent rep was booked. */
    var lastRepSource = Tracking.AUTO
        private set

    /**
     * The score the movement had actually reached when the last event fired.
     *
     * The count itself is cleared by [advance] on the way into the next movement, so by the time
     * a caller reads [reps] after an EXERCISE_DONE it is looking at the new movement's zero. The
     * voice used to work around that by announcing the *target* instead, which was right only
     * because finishing was the only way to leave a movement. Skipping is the other way, and the
     * athlete who did three push-ups and skipped is owed "three", not "ten".
     */
    var repsAtLastEvent = 0
        private set

    /**
     * What each movement of the round in progress actually scored, filled in as each is left.
     *
     * Reps used to be inferred from position — "past the push-ups" was taken to mean ten of them
     * — which is true only while the sole way past a movement is to finish it. SKIP means a
     * round can be completed with fewer reps in it than its targets, and a tally that keeps
     * crediting the targets is a tally that reports work nobody did.
     */
    private val bankedThisRound = linkedMapOf<Exercise, Int>()

    /**
     * The same, for every round already finished — kept per round rather than summed so that
     * [undoRep] can step back over a round boundary into the score that was really there.
     */
    private val bankedRounds = mutableListOf<Map<Exercise, Int>>()

    /** Details used by the video-regression reports for the most recent frame. */
    var diagnostics = FrameDiagnostics()
        private set

    /** Stable spelling for scenario files; it does not expose RepCounter's implementation enum. */
    val countingState: String
        get() = when (phase) {
            RepCounter.Phase.UNKNOWN -> "idle"
            RepCounter.Phase.DOWN -> "down"
            RepCounter.Phase.UP -> "up"
        }

    private var movingSince = 0L
    private val bar = BarZone()
    private var setupInProgress = false
    /** A fresh, on-bar dead hang is required before every pull-up count. */
    private var pullupDownSeen = false
    /** Consecutive unusable frames since the last good one, while a cycle is in flight. */
    private var pullupDropoutFrames = 0
    /** Straightest elbow angle seen while hanging, which scales the dead-hang test. */
    private var pullupExtendedElbow = Float.NaN
    /** Torso length when the current bar estimate was first established. */
    private var barTorso = Float.NaN
    /** Consecutive dead hangs a bar learned at a very different scale has refused. */
    private var barContradictions = 0
    /** Consecutive frames the hands have been overhead, gating what a bar may be learned from. */
    private var overheadFrames = 0
    /** When the current run of still, overhead hands began, or 0 while broken. */
    private var barSettleSince = 0L
    /** Hand position the current still run is measured from, or null while broken. */
    private var barSettleHands: Keypoint? = null

    /** True once a dead hang has taught the engine where the bar is. */
    val barKnown: Boolean get() = bar.established

    /** True while waiting for the athlete to take up the current movement's starting position. */
    var awaitingStart = false
        private set

    /** When the current run of correct, no-longer-extending posture began, or 0 while broken. */
    private var startPositionSince = 0L
    /** Smoothed signal while taking up a position, and the value the dwell was measured from. */
    private var startSmoothed = Float.NaN
    private var startReference = Float.NaN

    /**
     * True when this frame was refused for a reason the athlete could fix by moving.
     *
     * Distinct from simply being mid-rep: "Go down" is not a problem, whereas "Stand up to
     * start" or "Get on the bar" means nothing is being counted until something changes. The
     * UI uses it to decide when a hint is worth saying out loud.
     */
    var blocked = false
        private set

    /**
     * Where to draw the pull-up gate, or null while no bar is known.
     *
     * The overlay exists because the gates that refuse a rep are invisible: "Get on the bar" and
     * "Return to a dead hang" describe a box and a line the athlete cannot see. This is the
     * engine's own geometry, not a second estimate of it, so what is drawn is what is tested.
     */
    var barGuide: BarGuide? = null
        private set

    /**
     * Configures a recorded clip's bar from normalised video coordinates.
     *
     * This intentionally lives on the production engine, rather than in test-only code, so the
     * harness still uses the same bar gate as the app. The live camera leaves the bar automatic.
     */
    fun configureManualBar(
        yNormalized: Float,
        xMinNormalized: Float,
        xMaxNormalized: Float,
        frameWidth: Int,
        frameHeight: Int
    ) {
        require(frameWidth > 0 && frameHeight > 0) { "Frame dimensions must be positive" }
        bar.configureManual(
            y = yNormalized * frameHeight,
            xMin = xMinNormalized * frameWidth,
            xMax = xMaxNormalized * frameWidth
        )
        pullupDownSeen = false
        overheadFrames = 0
        barSettleSince = 0L
        barSettleHands = null
        counters.getValue(Exercise.PULLUP).requireFreshDown()
    }

    val reps: Int get() = counters.getValue(exercise).count
    val phase: RepCounter.Phase get() = counters.getValue(exercise).phase
    val signal: Float get() = counters.getValue(exercise).smoothed
    val learnedRange: Float get() = counters.getValue(exercise).learnedRange
    val calibrated: Boolean get() = counters.getValue(exercise).calibrated

    /**
     * Reps completed since the start of the current round, across all three movements.
     *
     * The movements already left contribute what they actually scored, not what they were asked
     * for. Those two only differ when something was skipped, which is exactly the case this
     * figure used to get wrong.
     */
    val repsThisRound: Int
        get() = bankedThisRound.values.sum() + reps

    val totalReps: Int get() = bankedRounds.sumOf { it.values.sum() } + repsThisRound

    /**
     * Every movement left, in order, with what it banked, then the one in progress.
     *
     * Read-only, and built from exactly the banks [totalReps] already sums — never from rounds
     * or a movement's target. That is what a Strava set list is required to be honest about
     * (see `WorkoutSets`): a movement SKIPped at three reps is a set of three, not a set of its
     * target, the same rule [totalReps] already holds for the session total.
     */
    val sets: List<WorkoutSet>
        get() {
            val list = mutableListOf<WorkoutSet>()
            bankedRounds.forEachIndexed { index, round ->
                round.forEach { (movement, banked) -> list += WorkoutSet(index + 1, movement, banked) }
            }
            bankedThisRound.forEach { (movement, banked) -> list += WorkoutSet(rounds + 1, movement, banked) }
            list += WorkoutSet(rounds + 1, exercise, reps)
            return list
        }

    fun reset() {
        counters.values.forEach { it.reset() }
        exercise = fixedExercise ?: Exercise.PULLUP
        rounds = 0
        hint = "Step into frame"
        bodyVisible = false
        movingSince = 0L
        setupInProgress = false
        pullupDownSeen = false
        pullupExtendedElbow = Float.NaN
        barTorso = Float.NaN
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0L
        barSettleHands = null
        awaitingStart = false
        startPositionSince = 0L
        startSmoothed = Float.NaN
        startReference = Float.NaN
        blocked = false
        manualReps = 0
        lastRepSource = Tracking.AUTO
        repsAtLastEvent = 0
        bankedThisRound.clear()
        bankedRounds.clear()
        diagnostics = FrameDiagnostics()
        bar.reset()
        barGuide = null
    }

    /** Advances past the current exercise without finishing it (manual override). */
    fun skipExercise(): RepEvent = advance()

    /** Books one rep by hand, for when the camera angle defeats the detector. */
    fun manualRep(): RepEvent {
        counters.getValue(exercise).forceIncrement()
        manualReps++
        lastRepSource = Tracking.MANUAL
        return settle()
    }

    /**
     * Takes back a rep the counter should not have scored.
     *
     * Steps backwards across movement and round boundaries, so undoing the first push-up of a
     * round returns you to the fifth pull-up rather than stranding the score at zero.
     */
    fun undoRep(): RepEvent {
        awaitingStart = false
        // Which rep is being taken back is not recorded, so undo assumes it was the last one
        // booked. Wrong only if the athlete taps +1, lets the camera score, then undoes twice —
        // and wrong by one in a figure that exists to be honest about roughly how much was
        // tapped, not to be audited.
        if (lastRepSource == Tracking.MANUAL && manualReps > 0) {
            manualReps--
            lastRepSource = Tracking.AUTO
        }
        val counter = counters.getValue(exercise)
        if (counter.count > 0) {
            counter.forceDecrement()
            repsAtLastEvent = counter.count
            return RepEvent.UNDO
        }
        if (exercise != Exercise.PULLUP) {
            exercise = exercise.previous()
            stepBackInto(exercise)
            return RepEvent.UNDO
        }
        if (rounds == 0) return RepEvent.NONE
        rounds--
        // The round being stepped back into is the one whose banked counts were just filed away.
        bankedThisRound.clear()
        bankedRounds.removeLastOrNull()?.let { bankedThisRound.putAll(it) }
        exercise = Exercise.SQUAT
        stepBackInto(Exercise.SQUAT)
        return RepEvent.UNDO
    }

    /**
     * Re-enters a movement already left, at one rep below what it actually scored.
     *
     * "One below its target" was the old answer, and it silently handed back reps that were
     * never done to anyone who had skipped the movement — undo would have been a way to invent
     * a score. What it scored is banked, so that is what it returns to.
     */
    private fun stepBackInto(movement: Exercise) {
        val banked = bankedThisRound.remove(movement) ?: movement.target
        counters.getValue(movement).setCount((banked - 1).coerceAtLeast(0))
        repsAtLastEvent = counters.getValue(movement).count
    }

    /**
     * Forgets every learned band, keeping the score.
     *
     * The bands describe this athlete as seen from where the phone was standing. A flip, or a
     * pause long enough for either to have moved, invalidates that without invalidating the reps
     * already counted.
     */
    fun recalibrate() {
        counters.values.forEach { it.resetBand() }
        // The bar's position was recorded in frame pixels, so a moved camera invalidates it.
        bar.reset()
        barGuide = null
        pullupDownSeen = false
        pullupExtendedElbow = Float.NaN
        barTorso = Float.NaN
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0L
        barSettleHands = null
        diagnostics = FrameDiagnostics()
    }

    /**
     * Scores a running-workout frame.
     *
     * [identityStable] comes from PoseDetector's tracked ROI. A single-pose model cannot name
     * people, but a lost ROI is the one reliable signal that this is no longer the same body;
     * treating it as a pause prevents a new person from completing a half-started pull-up.
     */
    fun onFrame(k: Array<Keypoint>, now: Long, identityStable: Boolean = true): RepEvent {
        if (setupInProgress) {
            hint = "Finish setup first"
            blocked = false
            diagnostics = frameDiagnostics(k, identityStable, rejection = hint)
            return RepEvent.NONE
        }
        val torso = PoseGeometry.torsoLength(k)
        if (torso == null || torso < 1f) {
            bodyVisible = false
            hint = "Step into frame"
            blocked = true
            if (exercise == Exercise.PULLUP) toleratePullupDropout()
            diagnostics = frameDiagnostics(k, identityStable, rejection = hint)
            return RepEvent.NONE
        }
        bodyVisible = true

        if (exercise == Exercise.PULLUP) return onPullupFrame(k, now, identityStable)

        val s = signalFor(k)
        if (s.isNaN()) {
            blocked = true
            diagnostics = frameDiagnostics(k, identityStable, rejection = hint)
            return RepEvent.NONE
        }

        val counter = counters.getValue(exercise)

        if (awaitingStart) {
            // Deliberately not fed to the counter at all. Lying face down reads as a full 180
            // degrees of knee extension, and letting that into the learned band lifts the top of
            // it above anything the athlete can reach standing — which stops every squat
            // counting rather than just the phantom one.
            blocked = true
            hint = exercise.startCue
            takeUpPosition(k, s, now, counter)
            diagnostics = frameDiagnostics(
                k, identityStable, scoringConfidenceAdequate = true, rejection = hint
            )
            return RepEvent.NONE
        }

        val counted = counter.update(s, now)
        diagnostics = frameDiagnostics(
            k, identityStable, scoringConfidenceAdequate = true, rejection = if (counted) null else hint
        )
        if (!counted) {
            hint = if (phase == RepCounter.Phase.DOWN) "Drive up" else "Go down"
            blocked = false
            diagnostics = frameDiagnostics(k, identityStable, scoringConfidenceAdequate = true, rejection = hint)
            return RepEvent.NONE
        }
        blocked = false
        lastRepSource = Tracking.AUTO
        return settle()
    }

    /**
     * Watches the athlete take up the movement, and opens the gate once they have.
     *
     * Two things have to be true together, and neither is sufficient alone. The posture has to be
     * right — upright for squats, down for push-ups — which is what rules out arriving while
     * still on the floor. And the joint that scores the movement has to have stopped opening,
     * which is what rules out arriving halfway up. Getting off the floor satisfies the first for
     * most of a second before it satisfies the second.
     */
    private fun takeUpPosition(k: Array<Keypoint>, s: Float, now: Long, counter: RepCounter) {
        if (!inStartPosition(k)) {
            startPositionSince = 0L
            startSmoothed = Float.NaN
            startReference = Float.NaN
            return
        }
        startSmoothed =
            if (startSmoothed.isNaN()) s
            else startSmoothed + START_SETTLE_SMOOTHING * (s - startSmoothed)
        // Any further opening restarts the clock, however slowly it is happening.
        if (startPositionSince == 0L || startSmoothed > startReference + START_SETTLE_DEGREES) {
            startPositionSince = now
            startReference = startSmoothed
            return
        }
        if (now - startPositionSince < START_POSITION_MS) return
        awaitingStart = false
        blocked = false
        // Arriving is not the top of a rep. Throwing away the climb that got here is the whole
        // point: otherwise standing up off the floor books one.
        counter.requireFreshDown()
    }

    /**
     * Whether the athlete is standing, or down on the floor, as the current movement requires.
     *
     * Only the torso's direction is tested. Both a plank and a standing body have straight legs,
     * so the knee angle that scores a squat cannot also decide whether the squat has begun.
     */
    private fun inStartPosition(k: Array<Keypoint>): Boolean = when (exercise) {
        // The bar, head and dead-hang gates already refuse anything that is not a pull-up.
        Exercise.PULLUP -> true
        Exercise.PUSHUP -> !PoseGeometry.upright(k)
        Exercise.SQUAT -> PoseGeometry.standing(k)
    }

    /** Advances to the next movement if the current one just hit its target. */
    private fun settle(): RepEvent {
        if (fixedExercise == null && reps >= exercise.target) return advance()
        repsAtLastEvent = reps
        return RepEvent.REP
    }

    private fun advance(): RepEvent {
        // Read before the counter is cleared: this is the number the movement really reached,
        // and after a skip it is the only record that it was not the target.
        repsAtLastEvent = reps
        bankedThisRound[exercise] = reps
        counters.getValue(exercise).resetCount()
        val wasLast = exercise == Exercise.SQUAT
        exercise = exercise.next()
        counters.getValue(exercise).resetCount()
        // Whatever the athlete does to get from the last movement into this one must not score.
        awaitingStart = exercise.startsFromPosition
        startPositionSince = 0L
        startSmoothed = Float.NaN
        startReference = Float.NaN
        return if (wasLast) {
            rounds++
            bankedRounds += bankedThisRound.toMap()
            bankedThisRound.clear()
            RepEvent.ROUND_DONE
        } else {
            RepEvent.EXERCISE_DONE
        }
    }

    // ── pre-workout check ─────────────────────────────────────────────────────

    /** Starts the check for the current movement, discarding any band learned earlier. */
    fun beginSetup() {
        counters.getValue(exercise).reset()
        movingSince = 0L
        bar.reset()
        barGuide = null
        setupInProgress = true
        pullupDownSeen = false
        pullupExtendedElbow = Float.NaN
        barTorso = Float.NaN
        barContradictions = 0
        overheadFrames = 0
        barSettleSince = 0L
        barSettleHands = null
        diagnostics = FrameDiagnostics()
    }

    /**
     * Watches a calibration rep and reports whether this camera placement can be worked with.
     *
     * The check is just the counter running before the clock does. Calibrating this way seeds
     * the band from the athlete's own range, so the first rep of the workout is judged against
     * a real measurement rather than the fallback floor — and a placement that cannot produce a
     * believable range is caught here, instead of quietly undercounting for twenty minutes.
     */
    fun onSetupFrame(k: Array<Keypoint>, now: Long, identityStable: Boolean = true): Setup {
        val counter = counters.getValue(exercise)
        val missing = PoseGeometry.missingJoints(k, exercise)
        if (missing.isNotEmpty()) {
            movingSince = 0L
            if (exercise == Exercise.PULLUP) toleratePullupDropout()
            diagnostics = frameDiagnostics(k, identityStable, rejection = "Missing ${missing.joinToString()}")
            return Setup(SetupStage.FRAMING, missing, counter.count, counter.learnedRange, counter.requiredRange)
        }
        if (movingSince == 0L) movingSince = now

        if (exercise == Exercise.PULLUP) {
            onPullupFrame(k, now, identityStable, settleWorkout = false)
        } else {
            val s = signalFor(k)
            if (!s.isNaN()) counter.update(s, now)
            diagnostics = frameDiagnostics(
                k, identityStable, scoringConfidenceAdequate = !s.isNaN(),
                rejection = if (s.isNaN()) hint else null
            )
        }

        val enough = counter.count >= CALIBRATION_REPS && counter.learnedRange >= counter.requiredRange
        val stage = when {
            enough -> SetupStage.READY
            now - movingSince > POOR_AFTER_MS -> SetupStage.POOR
            else -> SetupStage.MOVING
        }
        return Setup(stage, emptyList(), counter.count, counter.learnedRange, counter.requiredRange)
    }

    /** Zeroes the calibration reps but keeps the band they taught. */
    fun finishSetup() {
        counters.getValue(exercise).resetCount()
        setupInProgress = false
        // Setup may have ended at the top of its second calibration rep. A new counted rep still
        // has to begin with a fresh dead hang below the reset line.
        pullupDownSeen = false
        if (exercise == Exercise.PULLUP) counters.getValue(exercise).requireFreshDown()
    }

    private fun signalFor(k: Array<Keypoint>): Float = when (exercise) {
        // Pull-ups are handled by onPullupFrame(), which owns the bar/head/reset gates.
        Exercise.PULLUP -> Float.NaN
        Exercise.PUSHUP -> pushupSignal(k)
        Exercise.SQUAT -> squatSignal(k)
    }

    /**
     * The pull-up gate as the overlay draws it: the box both wrists must sit in, and the line
     * the head must drop back below before the next rep can arm.
     */
    data class BarGuide(
        val zone: BarZone.Bounds,
        val resetY: Float,
        val gateOpen: Boolean
    )

    // ── signals ───────────────────────────────────────────────────────────────

    /**
     * Mean elbow angle, negated: about -170 at a dead hang, about -60 with the chin over the bar.
     *
     * An earlier version measured how far the shoulders rose toward the hands, divided by torso
     * length. That undercounted badly for two compounding reasons. Dividing by torso length put
     * the hip keypoints in the denominator, and hips are the *least* reliable joints on someone
     * hanging with their knees bent behind them — a hip estimate drifting low inflates the
     * divisor and shrinks the signal until it no longer reaches the arming threshold. Worse, the
     * posture guard rejected any frame where the shoulders rose above the hands, which is
     * exactly what happens at the top of a strong pull-up: the better the rep, the more reliably
     * it was thrown away.
     *
     * An angle needs no normalisation, so nothing about the athlete's build, their distance from
     * the camera, or where MoveNet thinks their hips are can move the thresholds.
     */
    private data class PullupSample(
        val signal: Float,
        val deadHangBelowReset: Boolean,
        val headAboveBar: Boolean,
        val barGateOpen: Boolean
    )

    /**
     * Scores a pull-up only after the physical gates are true. RepCounter remains the only
     * component which can increment the score; this method only decides whether its input is
     * meaningful for the current tracked body.
     */
    private fun onPullupFrame(
        k: Array<Keypoint>,
        now: Long,
        identityStable: Boolean,
        settleWorkout: Boolean = true
    ): RepEvent {
        if (!identityStable) {
            hint = "Tracking…"
            blocked = true
            toleratePullupDropout()
            diagnostics = frameDiagnostics(k, false, rejection = hint)
            return RepEvent.NONE
        }

        val sample = pullupSample(k, now)
        if (sample == null) {
            blocked = true
            toleratePullupDropout()
            diagnostics = frameDiagnostics(k, true, rejection = hint)
            return RepEvent.NONE
        }

        pullupDropoutFrames = 0

        val counter = counters.getValue(Exercise.PULLUP)

        // Every readable on-bar frame is observed, so the band learns the athlete's real swing
        // even while the gates are shut. Only a frame that clears all of them may book a rep,
        // which is what stops an elbow-only partial from scoring. Withholding the samples
        // instead — the previous approach — left the counter judging reps against a band built
        // from a fraction of the movement.
        val mayCount = !sample.deadHangBelowReset && sample.headAboveBar && pullupDownSeen
        val counted = counter.update(sample.signal, now, mayCount = mayCount)

        if (sample.deadHangBelowReset) {
            // Observing here makes RepCounter's DOWN phase agree with the physical reset.
            if (counter.phase == RepCounter.Phase.DOWN) pullupDownSeen = true
            // Hanging at the bottom is where a pull-up starts, not a fault worth announcing.
            // But the athlete is told "Ready" off the back of this, and that has to mean the
            // next rep will actually score — which a hang that has not yet armed will not.
            blocked = !pullupDownSeen
            diagnostics = frameDiagnostics(
                k, true, scoringConfidenceAdequate = true, barGateOpen = sample.barGateOpen,
                headAboveBar = sample.headAboveBar
            )
            return RepEvent.NONE
        }

        if (!mayCount) {
            blocked = true
            hint = when {
                pullupDownSeen -> "Get your head over the bar"
                requiresDeadHang -> "Return to a dead hang"
                else -> "Lower all the way down"
            }
            diagnostics = frameDiagnostics(
                k, true, scoringConfidenceAdequate = true, barGateOpen = sample.barGateOpen,
                headAboveBar = sample.headAboveBar, rejection = hint
            )
            return RepEvent.NONE
        }

        diagnostics = frameDiagnostics(
            k, true, scoringConfidenceAdequate = true, barGateOpen = sample.barGateOpen,
            headAboveBar = sample.headAboveBar, rejection = if (counted) null else "Drive up"
        )
        blocked = false
        if (!counted) {
            hint = "Drive up"
            return RepEvent.NONE
        }

        // A second count cannot inherit this rep: a fresh reset below the bar is required.
        pullupDownSeen = false
        lastRepSource = Tracking.AUTO
        return if (settleWorkout) settle() else RepEvent.NONE
    }

    /** Validates a pull-up pose without mutating the counter. */
    private fun pullupSample(k: Array<Keypoint>, now: Long): PullupSample? {
        val leftWrist = k[KP.LEFT_WRIST]
        val rightWrist = k[KP.RIGHT_WRIST]
        if (!PoseGeometry.ok(leftWrist) || !PoseGeometry.ok(rightWrist)) {
            hint = "Show both hands"
            return null
        }
        if (!PoseGeometry.hangingFromBar(k)) {
            hint = "Hang from the bar"
            return null
        }
        // Hands overhead is not enough to call this a hang. Lying or leaning back under a bar for
        // an inverted row also puts the wrists above the hips, and every remaining gate then
        // passes: the bar is learned from the hands, the head crosses the line, and the elbow
        // swings a full range. A ten-step progression clip scored ten reps that way, three of
        // them horizontal rows. Only the direction the torso points separates the two families —
        // the same test the push-up path has always used to know the athlete is on the floor.
        //
        // Measured on that clip, as (hip.y - shoulder.y) / torso:
        //
        //     vertical pulls (wall, chair, banded, full)   0.92 .. 1.00, median 1.00
        //     low and mid inverted rows                    0.33 .. 0.86, median 0.63
        //     a HIGH inverted row, leaning back steeply     0.86 .. 0.98, median 0.90
        //
        // So the row family separates, but not all of it: a steeply inclined high row sits
        // inside the range real hangs occupy, and no threshold splits 0.90 from 0.92 without
        // inventing a precision the measurement does not have. The gate is therefore set where
        // the evidence supports it and no further — it removes the horizontal rows people
        // actually start a progression with, and a high row is left honestly unseparated rather
        // than rejected by a number chosen to look decisive.
        //
        // Returning null routes the frame through toleratePullupDropout(), so a brief wobble
        // mid-rep is absorbed by the existing dropout window, while a sustained row never arms a
        // cycle at all. That is the hysteresis, without a second state machine to keep in step.
        if (!PoseGeometry.upright(k)) {
            hint = "Hang vertically from the bar"
            return null
        }
        val hands = Keypoint(
            (leftWrist.x + rightWrist.x) / 2f,
            (leftWrist.y + rightWrist.y) / 2f,
            minOf(leftWrist.score, rightWrist.score)
        )
        val torso = PoseGeometry.torsoLength(k) ?: run {
            hint = "Step into frame"
            return null
        }
        val elbow = PoseGeometry.bilateralAngle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST
        )
        if (elbow.isNaN()) {
            hint = "Arms out of frame"
            return null
        }
        pullupExtendedElbow =
            if (pullupExtendedElbow.isNaN()) elbow else maxOf(pullupExtendedElbow, elbow)
        val deadHang = deadHangDegrees()

        // Refinement requires already passing the gate, so a bar learned in the wrong place can
        // otherwise lock the athlete out for the rest of the workout — which is exactly what a
        // clip mis-established during a walk-up did, rejecting 2377 of 2888 frames. A sustained
        // dead hang refused at a very different body scale is evidence that the estimate, not
        // the athlete, is in the wrong place.
        if (bar.established && elbow >= deadHang && !bar.holds(leftWrist, rightWrist, torso)) {
            val ratio =
                if (barTorso.isNaN() || barTorso <= 0f || torso <= 0f) 1f
                else maxOf(torso / barTorso, barTorso / torso)
            if (ratio > BAR_SCALE_CHANGE && ++barContradictions > MAX_BAR_CONTRADICTIONS) {
                bar.reset()
                barGuide = null
                barTorso = Float.NaN
                barContradictions = 0
                barSettleSince = 0L
                barSettleHands = null
            }
        } else {
            barContradictions = 0
        }

        // A straight-armed hang establishes an unknown bar. Once known, only observations that
        // are already on that bar may refine it; otherwise someone stepping off the bar could
        // slowly drag the learned line down to the floor.
        //
        // Establishing one from scratch additionally needs the hands *overhead*. Setting up a
        // resistance band means standing there holding it at chest height with straight arms for
        // several seconds, which satisfies every other test here — hands above the hips, elbows
        // extended — and taught the bar at the athlete's chest, a couple of hundred pixels below
        // the real one. Every subsequent rep was then refused with "Get on the bar", and because
        // refinement requires already passing the gate, it could never recover. Strict pull-ups
        // have no such phase, which is why only band footage found it.
        val overhead = PoseGeometry.handsOverhead(k, hands)
        overheadFrames = if (overhead) overheadFrames + 1 else 0
        // Seeing the nose below the hands is evidence, and is acted on at once — a real dead hang
        // still locates the bar on the first frame, which strict pull-ups depend on. Permission
        // inferred from a nose that could *not* be seen is not evidence, and has to persist.
        val mayLearn = overhead && (PoseGeometry.ok(k[KP.NOSE]) || overheadFrames >= OVERHEAD_HOLD_FRAMES)
        if (elbow >= deadHang &&
            (if (bar.established) bar.holds(leftWrist, rightWrist, torso) else mayLearn)
        ) {
            val wasEstablished = bar.established
            val half = gripHalfWidth(k) ?: 0f
            bar.observeHang(hands.x, hands.y, half)
            if (!wasEstablished) barTorso = torso
        }
        if (bar.established) {
            barSettleSince = 0L
            barSettleHands = null
        } else if (overhead) {
            settleBar(hands, gripHalfWidth(k) ?: 0f, torso, now)
        } else {
            // Not a hang, so the stillness of holding a band must not accumulate toward one.
            barSettleSince = 0L
            barSettleHands = null
        }
        val onBar = bar.holds(leftWrist, rightWrist, torso)
        barGuide = bar.bounds(torso)?.let {
            BarGuide(
                zone = it,
                resetY = it.lineY + HEAD_RESET_TORSOS * torso,
                gateOpen = onBar
            )
        }
        if (!onBar) {
            hint = "Get on the bar"
            return null
        }

        val nose = k[KP.NOSE]
        val barY = bar.lineY
        if (!PoseGeometry.ok(nose) || barY == null) {
            hint = if (!PoseGeometry.ok(nose)) "Show your head" else "Hang from the bar"
            return null
        }
        return PullupSample(
            signal = -elbow,
            deadHangBelowReset = (!requiresDeadHang || elbow >= deadHang) &&
                nose.y >= barY + HEAD_RESET_TORSOS * torso,
            headAboveBar = nose.y < barY,
            barGateOpen = true
        )
    }

    /**
     * Whether the bottom of a rep has to be a straight-armed hang.
     *
     * It does for a strict pull-up: that is the movement, and [LimitedExtensionPullupTest] holds
     * the line. It cannot for a band-assisted one — the band takes enough weight that the arms
     * may never straighten, so requiring it means the reset never arms and the athlete scores
     * zero all session with the counter working perfectly behind a gate they cannot open.
     *
     * What remains for the assisted variant is the head dropping back below the reset line, and
     * that is the conjunct worth keeping: it is a torso-scaled offset rather than an angle, so
     * the camera's viewpoint cannot flatten it, and a head a quarter-torso below the bar is at
     * the bottom of the movement whatever the elbows are doing. The head still has to clear the
     * bar to score, and [RepCounter] still requires the athlete's full learned travel, so a
     * relaxed bottom buys a shallower rep nothing.
     */
    private val requiresDeadHang: Boolean
        get() = profile.pull == PullVariant.STRICT_PULL_UP

    /**
     * Forget a partial pull-up until a fresh on-bar dead hang is observed.
     *
     * This is the hard reset, for when the athlete has genuinely left the bar. A frame that is
     * merely unreadable goes through [toleratePullupDropout] instead.
     */
    private fun invalidatePullupCycle() {
        pullupDownSeen = false
        pullupDropoutFrames = 0
        counters.getValue(Exercise.PULLUP).requireFreshDown()
    }

    /**
     * Absorbs a frame the pull-up gates could not read.
     *
     * A cycle already in flight survives a short run of them; a sustained run is indistinguishable
     * from having left the bar, so it ends the cycle.
     */
    private fun toleratePullupDropout() {
        if (!pullupDownSeen) {
            invalidatePullupCycle()
            return
        }
        if (++pullupDropoutFrames > MAX_DROPOUT_FRAMES) invalidatePullupCycle()
    }

    /**
     * The angle at which the arms read as straight for *this* camera placement.
     *
     * Never stricter than [DEAD_HANG_DEGREES]; a foreshortened view relaxes it to whatever full
     * extension actually projects as.
     */
    private fun deadHangDegrees(): Float =
        if (pullupExtendedElbow.isNaN()) DEAD_HANG_DEGREES
        else minOf(
            DEAD_HANG_DEGREES,
            maxOf(DEAD_HANG_FLOOR_DEGREES, pullupExtendedElbow - DEAD_HANG_SLACK_DEGREES)
        )

    /**
     * Locates the bar from hands simply held still overhead, when no dead hang has managed to.
     *
     * Strictly a fallback. A straight-armed hang still establishes the bar on the frame it
     * happens, so nothing about a strict pull-up reaches this at all. It exists because the
     * dead-hang route can never fire for some athletes: an elbow that does not reach
     * [DEAD_HANG_FLOOR_DEGREES] — limited extension, or a band taking enough weight that the
     * arms never straighten — leaves the bar unknown, and an unknown bar has no [BarZone.lineY],
     * so every pull-up frame is refused before the gates are even consulted. The whole workout
     * then scores zero under "Hang from the bar". Not being able to *find* the bar is not a
     * movement standard, it is a lockout: the head and bar gates still have to be satisfied
     * afterwards, and on the strict variant so does the dead hang.
     *
     * Stillness is the evidence rather than the elbow, because stillness is what separates
     * hanging from the walk-up that previously taught a bar in the wrong place. The same
     * argument as [takeUpPosition]: a dwell on a position that has stopped changing, rather
     * than a threshold on an angle that the camera's viewpoint can flatten.
     */
    private fun settleBar(hands: Keypoint, halfGrip: Float, torso: Float, now: Long) {
        val reference = barSettleHands
        if (reference == null ||
            hypot(hands.x - reference.x, hands.y - reference.y) > BAR_SETTLE_DRIFT_TORSOS * torso
        ) {
            barSettleSince = now
            barSettleHands = hands
            return
        }
        if (now - barSettleSince < BAR_SETTLE_MS) return
        bar.observeHang(hands.x, hands.y, halfGrip)
        barTorso = torso
        barSettleSince = 0L
        barSettleHands = null
    }

    /** Half the distance between the hands, for the bar's horizontal span. */
    private fun gripHalfWidth(k: Array<Keypoint>): Float? {
        val l = k[KP.LEFT_WRIST]
        val r = k[KP.RIGHT_WRIST]
        if (!PoseGeometry.ok(l) || !PoseGeometry.ok(r)) return null
        return abs(l.x - r.x) / 2f
    }

    /** Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout. */
    private fun pushupSignal(k: Array<Keypoint>): Float {
        // Guard against a pull-up being scored as a push-up, using the same overhead test.
        if (PoseGeometry.hangingFromBar(k)) {
            hint = "Get on the floor"
            return Float.NaN
        }
        return PoseGeometry.bilateralAngle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST
        )
    }

    /** Mean knee angle in degrees; small in the hole, ~180 standing. */
    private fun squatSignal(k: Array<Keypoint>): Float = PoseGeometry.bilateralAngle(
        k,
        KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE,
        KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE
    ).also { if (it.isNaN()) hint = "Show your legs to the camera" }

    private fun frameDiagnostics(
        k: Array<Keypoint>,
        identityStable: Boolean,
        scoringConfidenceAdequate: Boolean = false,
        barGateOpen: Boolean = false,
        headAboveBar: Boolean = false,
        rejection: String? = null
    ) = FrameDiagnostics(
        minimumConfidence = k.minOfOrNull { it.score } ?: 0f,
        scoringConfidenceAdequate = scoringConfidenceAdequate,
        poseLegible = poseLegible(k),
        identityStable = identityStable,
        barGateOpen = barGateOpen,
        headAboveBar = headAboveBar,
        deadHangSinceLastRep = pullupDownSeen,
        resetBelowBarSeen = pullupDownSeen,
        rejectionReason = rejection
    )

    /**
     * Whether every joint the current movement scores from was confidently seen.
     *
     * The joint lists are the ones each signal actually consults: pull-ups and push-ups both run
     * on the shoulder-elbow-wrist chain with the hips supplying torso scale, and squats on the
     * hip-knee-ankle chain with the shoulders doing the same. Asking for *all* of them, rather
     * than enough of them to compute an angle, is what makes this fall before the score does.
     *
     * Wrists are the joint that matters most here and the one that goes first: darkening a clip
     * until it stopped counting left "Show both hands" as the dominant refusal every time, which
     * is why pull-ups fail so much sooner than the other two movements.
     */
    private fun poseLegible(k: Array<Keypoint>): Boolean {
        val joints = when (exercise) {
            Exercise.PULLUP, Exercise.PUSHUP -> intArrayOf(
                KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_ELBOW, KP.RIGHT_ELBOW,
                KP.LEFT_WRIST, KP.RIGHT_WRIST, KP.LEFT_HIP, KP.RIGHT_HIP
            )
            Exercise.SQUAT -> intArrayOf(
                KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER, KP.LEFT_HIP, KP.RIGHT_HIP,
                KP.LEFT_KNEE, KP.RIGHT_KNEE, KP.LEFT_ANKLE, KP.RIGHT_ANKLE
            )
        }
        return joints.all { PoseGeometry.ok(k[it]) }
    }
}
