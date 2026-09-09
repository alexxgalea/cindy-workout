package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.acos
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
    private val fixedExercise: Exercise? = null
) {

    private companion object {
        /** MoveNet confidence below which a keypoint is treated as unseen. */
        const val MIN_SCORE = 0.30f
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
        /** How far below the bar the head must return before another pull-up can arm. */
        const val HEAD_RESET_TORSOS = 0.25f
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
         * How far the shoulders must sit above the hips, in torso lengths, to call the athlete
         * upright.
         *
         * A plank and a standing body both have straight legs, so the knee angle cannot tell
         * them apart — only the direction the torso is pointing can. A vertical torso scores
         * 1.0 and a horizontal one 0.0; the threshold leaves room for the forward lean of a
         * real squat and for a phone standing on the floor looking up.
         */
        const val UPRIGHT_TORSOS = 0.7f
        /**
         * How far the knees must sit below the hips, in torso lengths, to call the athlete stood
         * up rather than gathered in a crouch.
         *
         * A vertical torso is not standing. People get up off the floor by bringing the torso
         * upright first and collecting themselves on their haunches, which reads as upright for
         * most of a second — long enough to open a gate waiting only for that, after which the
         * drive out of the crouch scored as a rep. Standing carries the hips a whole thigh above
         * the knees; a crouch puts them level with, or below, them.
         *
         * An offset rather than a knee angle, on purpose: an angle threshold is what locked out
         * the athlete whose foreshortened full extension only read 145 degrees.
         */
        const val STANDING_TORSOS = 0.5f
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
        counters.getValue(Exercise.PULLUP).requireFreshDown()
    }

    val reps: Int get() = counters.getValue(exercise).count
    val phase: RepCounter.Phase get() = counters.getValue(exercise).phase
    val signal: Float get() = counters.getValue(exercise).smoothed
    val learnedRange: Float get() = counters.getValue(exercise).learnedRange
    val calibrated: Boolean get() = counters.getValue(exercise).calibrated

    /** Reps completed since the start of the current round, across all three movements. */
    val repsThisRound: Int
        get() = Exercise.entries.take(exercise.ordinal).sumOf { it.target } + reps

    val totalReps: Int get() = rounds * 30 + repsThisRound

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
        awaitingStart = false
        startPositionSince = 0L
        startSmoothed = Float.NaN
        startReference = Float.NaN
        blocked = false
        diagnostics = FrameDiagnostics()
        bar.reset()
        barGuide = null
    }

    /** Advances past the current exercise without finishing it (manual override). */
    fun skipExercise(): RepEvent = advance()

    /** Books one rep by hand, for when the camera angle defeats the detector. */
    fun manualRep(): RepEvent {
        counters.getValue(exercise).forceIncrement()
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
        val counter = counters.getValue(exercise)
        if (counter.count > 0) {
            counter.forceDecrement()
            return RepEvent.UNDO
        }
        if (exercise != Exercise.PULLUP) {
            exercise = exercise.previous()
            counters.getValue(exercise).setCount(exercise.target - 1)
            return RepEvent.UNDO
        }
        if (rounds == 0) return RepEvent.NONE
        rounds--
        exercise = Exercise.SQUAT
        counters.getValue(exercise).setCount(Exercise.SQUAT.target - 1)
        return RepEvent.UNDO
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
        val torso = torsoLength(k)
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
        Exercise.PUSHUP -> !upright(k)
        Exercise.SQUAT -> standing(k)
    }

    /** True when the shoulders sit well above the hips: torso vertical, not lying down. */
    private fun upright(k: Array<Keypoint>): Boolean {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return false
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val torso = hypot(sh.x - hp.x, sh.y - hp.y)
        if (torso < 1f) return false
        return (hp.y - sh.y) >= UPRIGHT_TORSOS * torso
    }

    /** Upright *and* stood up on the legs, rather than folded over them in a crouch. */
    private fun standing(k: Array<Keypoint>): Boolean {
        if (!upright(k)) return false
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val kn = midpoint(k, KP.LEFT_KNEE, KP.RIGHT_KNEE) ?: return false
        val torso = torsoLength(k) ?: return false
        return (kn.y - hp.y) >= STANDING_TORSOS * torso
    }

    /** Advances to the next movement if the current one just hit its target. */
    private fun settle(): RepEvent =
        if (fixedExercise == null && reps >= exercise.target) advance() else RepEvent.REP

    private fun advance(): RepEvent {
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
        val missing = missingJoints(k)
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

    /** Joints the current movement cannot be judged without, named for a human. */
    private fun missingJoints(k: Array<Keypoint>): List<String> {
        val needed = when (exercise) {
            Exercise.PULLUP, Exercise.PUSHUP -> listOf(
                "shoulders" to (KP.LEFT_SHOULDER to KP.RIGHT_SHOULDER),
                "elbows" to (KP.LEFT_ELBOW to KP.RIGHT_ELBOW),
                "hands" to (KP.LEFT_WRIST to KP.RIGHT_WRIST),
                "hips" to (KP.LEFT_HIP to KP.RIGHT_HIP)
            )
            Exercise.SQUAT -> listOf(
                "shoulders" to (KP.LEFT_SHOULDER to KP.RIGHT_SHOULDER),
                "hips" to (KP.LEFT_HIP to KP.RIGHT_HIP),
                "knees" to (KP.LEFT_KNEE to KP.RIGHT_KNEE),
                "ankles" to (KP.LEFT_ANKLE to KP.RIGHT_ANKLE)
            )
        }
        // midpoint() accepts either side, so a joint counts as seen if one of the pair is.
        return needed.filter { midpoint(k, it.second.first, it.second.second) == null }.map { it.first }
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

        val sample = pullupSample(k)
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
            hint = if (!pullupDownSeen) "Return to a dead hang" else "Get your head over the bar"
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
        return if (settleWorkout) settle() else RepEvent.NONE
    }

    /** Validates a pull-up pose without mutating the counter. */
    private fun pullupSample(k: Array<Keypoint>): PullupSample? {
        val leftWrist = k[KP.LEFT_WRIST]
        val rightWrist = k[KP.RIGHT_WRIST]
        if (!ok(leftWrist) || !ok(rightWrist)) {
            hint = "Show both hands"
            return null
        }
        if (!hangingFromBar(k)) {
            hint = "Hang from the bar"
            return null
        }
        val hands = Keypoint(
            (leftWrist.x + rightWrist.x) / 2f,
            (leftWrist.y + rightWrist.y) / 2f,
            minOf(leftWrist.score, rightWrist.score)
        )
        val torso = torsoLength(k) ?: run {
            hint = "Step into frame"
            return null
        }
        val elbow = bilateralAngle(
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
            }
        } else {
            barContradictions = 0
        }

        // A straight-armed hang establishes an unknown bar. Once known, only observations that
        // are already on that bar may refine it; otherwise someone stepping off the bar could
        // slowly drag the learned line down to the floor.
        if (elbow >= deadHang &&
            (!bar.established || bar.holds(leftWrist, rightWrist, torso))
        ) {
            val wasEstablished = bar.established
            val half = gripHalfWidth(k) ?: 0f
            bar.observeHang(hands.x, hands.y, half)
            if (!wasEstablished) barTorso = torso
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
        if (!ok(nose) || barY == null) {
            hint = if (!ok(nose)) "Show your head" else "Hang from the bar"
            return null
        }
        return PullupSample(
            signal = -elbow,
            deadHangBelowReset = elbow >= deadHang &&
                nose.y >= barY + HEAD_RESET_TORSOS * torso,
            headAboveBar = nose.y < barY,
            barGateOpen = true
        )
    }

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

    /** Half the distance between the hands, for the bar's horizontal span. */
    private fun gripHalfWidth(k: Array<Keypoint>): Float? {
        val l = k[KP.LEFT_WRIST]
        val r = k[KP.RIGHT_WRIST]
        if (!ok(l) || !ok(r)) return null
        return abs(l.x - r.x) / 2f
    }

    /**
     * Hands overhead, tested against the hips rather than the shoulders.
     *
     * The shoulders climb past the hands at the top of a good rep, so gating on them rejects the
     * peak of the movement. The hips stay well below the hands throughout, which separates
     * hanging from a push-up without discarding the reps worth counting.
     */
    private fun hangingFromBar(k: Array<Keypoint>): Boolean {
        val hip = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return false
        val wr = midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        return wr.y < hip.y
    }

    /** Mean elbow angle in degrees; small at the bottom of a push-up, ~180 at lockout. */
    private fun pushupSignal(k: Array<Keypoint>): Float {
        // Guard against a pull-up being scored as a push-up, using the same overhead test.
        if (hangingFromBar(k)) {
            hint = "Get on the floor"
            return Float.NaN
        }
        return bilateralAngle(
            k,
            KP.LEFT_SHOULDER, KP.LEFT_ELBOW, KP.LEFT_WRIST,
            KP.RIGHT_SHOULDER, KP.RIGHT_ELBOW, KP.RIGHT_WRIST
        )
    }

    /** Mean knee angle in degrees; small in the hole, ~180 standing. */
    private fun squatSignal(k: Array<Keypoint>): Float = bilateralAngle(
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
        identityStable = identityStable,
        barGateOpen = barGateOpen,
        headAboveBar = headAboveBar,
        deadHangSinceLastRep = pullupDownSeen,
        resetBelowBarSeen = pullupDownSeen,
        rejectionReason = rejection
    )

    // ── geometry helpers ──────────────────────────────────────────────────────

    private fun ok(p: Keypoint) = p.score >= MIN_SCORE

    private fun midpoint(k: Array<Keypoint>, a: Int, b: Int): Keypoint? {
        val pa = k[a]
        val pb = k[b]
        return when {
            ok(pa) && ok(pb) -> Keypoint((pa.x + pb.x) / 2f, (pa.y + pb.y) / 2f, minOf(pa.score, pb.score))
            ok(pa) -> pa
            ok(pb) -> pb
            else -> null
        }
    }

    private fun torsoLength(k: Array<Keypoint>): Float? {
        val sh = midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return null
        val hp = midpoint(k, KP.LEFT_HIP, KP.RIGHT_HIP) ?: return null
        return hypot(sh.x - hp.x, sh.y - hp.y)
    }

    /** Averages the same joint angle on both sides, using whichever sides are confidently seen. */
    private fun bilateralAngle(
        k: Array<Keypoint>,
        la: Int, lb: Int, lc: Int,
        ra: Int, rb: Int, rc: Int
    ): Float {
        val l = angle(k[la], k[lb], k[lc])
        val r = angle(k[ra], k[rb], k[rc])
        return when {
            !l.isNaN() && !r.isNaN() -> (l + r) / 2f
            !l.isNaN() -> l
            !r.isNaN() -> r
            else -> Float.NaN
        }
    }

    /** Interior angle at [b], in degrees, or NaN if any vertex is not confidently seen. */
    private fun angle(a: Keypoint, b: Keypoint, c: Keypoint): Float {
        if (!ok(a) || !ok(b) || !ok(c)) return Float.NaN
        val abx = a.x - b.x
        val aby = a.y - b.y
        val cbx = c.x - b.x
        val cby = c.y - b.y
        val mag = hypot(abx, aby) * hypot(cbx, cby)
        if (mag < 1e-4f) return Float.NaN
        val cos = ((abx * cbx + aby * cby) / mag).coerceIn(-1f, 1f)
        return Math.toDegrees(acos(cos).toDouble()).toFloat()
    }
}
