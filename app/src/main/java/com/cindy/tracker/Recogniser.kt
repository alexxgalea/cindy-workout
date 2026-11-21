package com.cindy.tracker

import kotlin.math.hypot

/** Where the athlete's body is. See the glossary: a [Position] is not a movement. */
enum class Position(val id: String, val label: String) {
    NONE("none", "no position"),
    ON_THE_BAR("on_the_bar", "on the bar"),
    ON_THE_FLOOR("on_the_floor", "on the floor"),
    STANDING("standing", "standing")
}

/**
 * What the athlete is doing, as recognition names it. Each movement starts from one [position].
 * The enum [Exercise] stays the engine's own word for the same three; a movement is what
 * recognition reports.
 */
enum class Movement(val id: String, val exercise: Exercise, val position: Position) {
    PULL_UPS("pull_ups", Exercise.PULLUP, Position.ON_THE_BAR),
    PUSH_UPS("push_ups", Exercise.PUSHUP, Position.ON_THE_FLOOR),
    SQUATS("squats", Exercise.SQUAT, Position.STANDING);

    val label: String get() = exercise.label

    companion object {
        /** The movement that starts from [position], or none for no position. */
        fun at(position: Position): Movement? = entries.firstOrNull { it.position == position }
    }
}

/**
 * What recognition makes of the frames so far.
 *
 * - [movement] is the movement recognised, or none. It stays until a different movement is
 *   confirmed.
 * - [candidate] is a movement whose position is entered and that has counted some reps but not
 *   yet [Recogniser.CONFIRMING_REPS]; [candidateReps] says how many. Nothing here is recognised.
 * - [tally] is the reps recognition has seen per movement, confirming reps included. A candidate's
 *   reps are not in it until the movement is confirmed.
 */
data class Recognition(
    val position: Position,
    val movement: Movement? = null,
    val candidate: Movement? = null,
    val candidateReps: Int = 0,
    val tally: Map<Movement, Int> = NO_REPS
) {
    companion object {
        val NO_REPS: Map<Movement, Int> = Movement.entries.associateWith { 0 }

        /** Nothing seen yet: no position, no movement, no reps. */
        val NONE = Recognition(Position.NONE)
    }
}

/**
 * Works out the athlete's [Position] on every analysed frame.
 *
 * A position is a state, not a per-frame verdict. Each frame points at one position at most; it is
 * entered once the frames have kept pointing at it for [ENTRY_MS], and then kept by a rule of its
 * own that is looser than the rule that entered it:
 *
 * - **On the bar**: entered when the hands are overhead, at least [HANDS_OVERHEAD_TORSOS] of a
 *   torso above the shoulders, so hands behind the head in a squat do not enter it. It wins over
 *   standing, because a hang is also upright with straight legs. Kept while the hands stay above
 *   the shoulders at all, as they do at the top of a pull-up, and through up to [KEEP_MS] without
 *   them.
 * - **Standing**: entered when the torso is upright and every shin that is seen stands under its
 *   knee. Kept by the shins alone, so the forward lean at the bottom of a squat stays standing,
 *   and through up to [KEEP_MS] without them.
 * - **On the floor**: entered by any seen torso that is neither on the bar nor on its legs, which
 *   takes in a plank from the side or head-on, a knee push-up and kneeling. Kept until another
 *   position is entered.
 * - **None**: where every session starts, and where the bar and standing go when they are lost.
 *
 * The bar and standing are the two positions that can be lost, and while one is still kept the
 * floor never takes its place, nor does standing take the bar's. The way out is through none,
 * with a fresh [ENTRY_MS] there. A hang that loses its hands for half a second must not turn into
 * standing, nor a squat that loses its legs into the floor.
 *
 * A frame whose identity is not stable is no evidence for any test: it enters nothing, and it
 * counts towards leaving a position.
 *
 * ### Movements
 *
 * The entered position picks the one counter that runs: pull-ups on the bar, push-ups on the
 * floor, squats standing. The recogniser owns one fixed-movement [WorkoutEngine] per movement,
 * built from the athlete's [profile] so a knee push-up or a band-assisted pull-up is counted as
 * the athlete chose, and only the engine of the position that is entered is fed a frame. These
 * engines are its own: nothing here touches the workout's counting. It reads no setup check; the
 * pull-up engine learns the bar from a still hang as it does mid-workout. The smart-squats switch
 * stays Cindy's alone, so squats are always counted by the plain counter.
 *
 * Arriving in a position drops the climb in flight in that movement's engine
 * ([WorkoutEngine.dropClimbOnArrival]), so standing up off the floor is not booked as a squat.
 * That is deliberately not the engine's own start gate, which loses whole sets the athlete is
 * already in.
 *
 * A movement is confirmed at the [CONFIRMING_REPS]th rep its engine counts in one visit to its
 * position, and those reps are part of its tally. A visit ends when the position changes. Before
 * confirmation nothing is recognised, and a single rep that is left behind is forgotten, because
 * being late is better than being wrong. A confirmed movement stays recognised until a different
 * one is confirmed, and returning to its position counts again at once.
 *
 * Time is the frame clock in milliseconds, never a frame count: the phone analyses between 8 and
 * 30 frames a second and the same rules have to hold at every rate.
 */
class Recogniser(private val profile: CindyProfile = CindyProfile.STANDARD) {

    private var engines = buildEngines()

    private var movement: Movement? = null
    private var candidate: Movement? = null
    private var candidateReps = 0
    private val tally = Movement.entries.associateWithTo(mutableMapOf()) { 0 }

    private fun buildEngines(): Map<Movement, WorkoutEngine> = Movement.entries.associateWith {
        WorkoutEngine(fixedExercise = it.exercise, profile = profile)
    }

    private var position = Position.NONE

    /** The position the frames are currently pointing at, and since when, for the entry dwell. */
    private var pointingAt = Position.NONE
    private var pointingSince = 0L

    /** The last time the kept position's own rule held, for the gap it may be kept through. */
    private var lastHeld = 0L

    fun onFrame(k: Array<Keypoint>, now: Long, identityStable: Boolean = true): Recognition {
        val before = position
        val frame = if (identityStable) read(k) else NO_EVIDENCE
        keep(frame, now)
        point(frame.pointsTo, now)
        enter(now)
        if (position != before) arrive()
        count(k, now, identityStable)
        return Recognition(position, movement, candidate, candidateReps, tally.toMap())
    }

    fun reset() {
        position = Position.NONE
        pointingAt = Position.NONE
        pointingSince = 0L
        lastHeld = 0L
        engines = buildEngines()
        movement = null
        candidate = null
        candidateReps = 0
        tally.keys.forEach { tally[it] = 0 }
    }

    /**
     * The camera or the athlete has moved: every engine forgets what it learned in the old framing
     * (the band, the bar), as Cindy's engine does ([WorkoutEngine.recalibrate]). The position, the
     * movement and the tally stay: what was seen is still what was seen.
     */
    fun recalibrate() {
        engines.values.forEach { it.recalibrate() }
    }

    /**
     * The position has changed, so the visit that was counting candidate reps is over, and the
     * engine of the position now entered must not book the climb that brought the athlete here.
     */
    private fun arrive() {
        candidate = null
        candidateReps = 0
        Movement.at(position)?.let { engines.getValue(it).dropClimbOnArrival() }
    }

    /** Feeds this frame to the one engine whose position is entered, and books the rep it counts. */
    private fun count(k: Array<Keypoint>, now: Long, identityStable: Boolean) {
        val counting = Movement.at(position) ?: return
        val event = engines.getValue(counting).onFrame(k, now, identityStable)
        if (event != RepEvent.REP) return
        if (counting == movement) {
            tally[counting] = tally.getValue(counting) + 1
            return
        }
        candidate = counting
        candidateReps++
        if (candidateReps < CONFIRMING_REPS) return
        // The confirming reps are the movement's first reps, not reps recognition spent on finding it.
        movement = counting
        tally[counting] = tally.getValue(counting) + candidateReps
        candidate = null
        candidateReps = 0
    }

    /** Leaves the bar or standing once its own rule has not held for longer than [KEEP_MS]. */
    private fun keep(frame: Frame, now: Long) {
        val holds = when (position) {
            Position.ON_THE_BAR -> frame.handsAboveShoulders
            Position.STANDING -> frame.shinsUnderKnees
            else -> return
        }
        if (holds) {
            lastHeld = now
        } else if (now - lastHeld > KEEP_MS) {
            position = Position.NONE
            // Whatever the frames were pointing at while the position was kept has not been
            // held since it was lost.
            pointingAt = Position.NONE
        }
    }

    private fun point(reading: Position, now: Long) {
        if (reading != pointingAt) {
            pointingAt = reading
            pointingSince = now
        }
    }

    private fun enter(now: Long) {
        if (pointingAt == Position.NONE || pointingAt == position) return
        if (now - pointingSince < ENTRY_MS) return
        if (!canReplace(position, pointingAt)) return
        position = pointingAt
        lastHeld = now
    }

    /** What may take the place of the position being kept; everything may take the place of none. */
    private fun canReplace(kept: Position, entering: Position): Boolean = when (entering) {
        Position.ON_THE_BAR -> true
        Position.STANDING -> kept != Position.ON_THE_BAR
        Position.ON_THE_FLOOR -> kept == Position.NONE
        Position.NONE -> false
    }

    private class Frame(
        val handsOverhead: Boolean,
        val handsAboveShoulders: Boolean,
        val shinsUnderKnees: Boolean,
        val upright: Boolean,
        val torsoSeen: Boolean
    ) {
        /** The position this frame alone points at, or none. */
        val pointsTo: Position
            get() = when {
                handsOverhead -> Position.ON_THE_BAR
                upright && shinsUnderKnees -> Position.STANDING
                torsoSeen -> Position.ON_THE_FLOOR
                else -> Position.NONE
            }
    }

    private fun read(k: Array<Keypoint>): Frame {
        val torso = PoseGeometry.torsoLength(k)
        return Frame(
            handsOverhead = handsOverhead(k, torso),
            handsAboveShoulders = handsAboveShoulders(k),
            shinsUnderKnees = shinsUnderKnees(k),
            upright = PoseGeometry.upright(k),
            torsoSeen = (torso ?: 0f) >= MIN_TORSO_PX
        )
    }

    private fun handsAboveShoulders(k: Array<Keypoint>): Boolean {
        val hands = PoseGeometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        val shoulders = PoseGeometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return false
        return hands.y < shoulders.y
    }

    /**
     * The hands are above the shoulders by [HANDS_OVERHEAD_TORSOS] of a torso, as they are on a bar
     * and are not behind the head. Without a torso to measure by, the hands are not overhead.
     */
    private fun handsOverhead(k: Array<Keypoint>, torso: Float?): Boolean {
        if (torso == null || torso < MIN_TORSO_PX) return false
        val hands = PoseGeometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        val shoulders = PoseGeometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return false
        return shoulders.y - hands.y >= HANDS_OVERHEAD_TORSOS * torso
    }

    /**
     * Every shin that is seen stands under its knee, and at least one is seen.
     *
     * The ankle has to sit at least [SHIN_UNDER_KNEE_THIGHS] of a thigh below the knee, a ratio to
     * the athlete's own thigh so the distance from the camera does not matter. Each side is judged
     * on its own joints: a midpoint would let a seen leg stand in for an unseen one. A shin that is
     * seen but cannot be measured (no hip on its side) refuses, because a missing joint is never
     * permission.
     */
    private fun shinsUnderKnees(k: Array<Keypoint>): Boolean {
        var seen = 0
        for ((hip, knee, ankle) in LEGS) {
            if (!PoseGeometry.ok(k[knee]) || !PoseGeometry.ok(k[ankle])) continue
            if (!PoseGeometry.ok(k[hip])) return false
            val thigh = hypot(k[hip].x - k[knee].x, k[hip].y - k[knee].y)
            if (thigh < MIN_THIGH_PX) return false
            if (k[ankle].y - k[knee].y < SHIN_UNDER_KNEE_THIGHS * thigh) return false
            seen++
        }
        return seen > 0
    }

    companion object {
        /** The rep at which a movement is confirmed. One could be a stray gesture. */
        const val CONFIRMING_REPS = 2

        /** How long the frames must keep pointing at a position before it is entered, as the start gate waits. */
        private const val ENTRY_MS = 500L

        /** How long the bar or standing is kept without its own rule holding. */
        private const val KEEP_MS = 1_000L

        /**
         * How far under its knee a seen ankle must be, in thighs, for the shin to stand. Measured on
         * the Cindy clip with MoveNet Thunder: kneeling never put an ankle more than 0.05 thighs
         * below the knee, standing and squatting never put one less than about 0.6.
         */
        private const val SHIN_UNDER_KNEE_THIGHS = 0.5f

        /** A thigh shorter than this cannot be measured against. */
        private const val MIN_THIGH_PX = 1f

        /** A torso shorter than this is shoulders and hips on top of each other, not a torso. */
        private const val MIN_TORSO_PX = 1f

        /**
         * How far above the shoulders the hands must be, in torsos, to enter the bar. Measured on
         * the owner's gym films and the Cindy clip: hands behind the head in a squat never went
         * past about 0.35 of a torso, a hang reached 0.8 to 1.2, and 0.4 to 0.6 scored the same.
         */
        private const val HANDS_OVERHEAD_TORSOS = 0.5f

        /** Each leg's hip, knee and ankle. */
        private val LEGS = listOf(
            Triple(KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE),
            Triple(KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE)
        )

        private val NO_EVIDENCE = Frame(
            handsOverhead = false,
            handsAboveShoulders = false,
            shinsUnderKnees = false,
            upright = false,
            torsoSeen = false
        )
    }
}
