package com.cindy.tracker

import kotlin.math.hypot

/** Where the athlete's body is. See the glossary: a [Position] is not a movement. */
enum class Position(val id: String, val label: String) {
    NONE("none", "no position"),
    ON_THE_BAR("on_the_bar", "on the bar"),
    ON_THE_FLOOR("on_the_floor", "on the floor"),
    STANDING("standing", "standing")
}

/** What recognition makes of the frames so far. */
data class Recognition(val position: Position)

/**
 * Works out the athlete's [Position] on every analysed frame.
 *
 * A position is a state, not a per-frame verdict. Each frame points at one position at most; it is
 * entered once the frames have kept pointing at it for [ENTRY_MS], and then kept by a rule of its
 * own that is looser than the rule that entered it:
 *
 * - **On the bar**: entered when the hands are above the shoulders. It wins over standing, because
 *   a hang is also upright with straight legs. Kept while the hands stay above the shoulders, and
 *   through up to [KEEP_MS] without them.
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
 * Time is the frame clock in milliseconds, never a frame count: the phone analyses between 8 and
 * 30 frames a second and the same rules have to hold at every rate.
 */
class Recogniser {

    private var position = Position.NONE

    /** The position the frames are currently pointing at, and since when, for the entry dwell. */
    private var pointingAt = Position.NONE
    private var pointingSince = 0L

    /** The last time the kept position's own rule held, for the gap it may be kept through. */
    private var lastHeld = 0L

    fun onFrame(k: Array<Keypoint>, now: Long, identityStable: Boolean = true): Recognition {
        val frame = if (identityStable) read(k) else NO_EVIDENCE
        keep(frame, now)
        point(frame.pointsTo, now)
        enter(now)
        return Recognition(position)
    }

    fun reset() {
        position = Position.NONE
        pointingAt = Position.NONE
        pointingSince = 0L
        lastHeld = 0L
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
        val handsAboveShoulders: Boolean,
        val shinsUnderKnees: Boolean,
        val upright: Boolean,
        val torsoSeen: Boolean
    ) {
        /** The position this frame alone points at, or none. */
        val pointsTo: Position
            get() = when {
                handsAboveShoulders -> Position.ON_THE_BAR
                upright && shinsUnderKnees -> Position.STANDING
                torsoSeen -> Position.ON_THE_FLOOR
                else -> Position.NONE
            }
    }

    private fun read(k: Array<Keypoint>) = Frame(
        handsAboveShoulders = handsAboveShoulders(k),
        shinsUnderKnees = shinsUnderKnees(k),
        upright = PoseGeometry.upright(k),
        torsoSeen = (PoseGeometry.torsoLength(k) ?: 0f) >= MIN_TORSO_PX
    )

    private fun handsAboveShoulders(k: Array<Keypoint>): Boolean {
        val hands = PoseGeometry.midpoint(k, KP.LEFT_WRIST, KP.RIGHT_WRIST) ?: return false
        val shoulders = PoseGeometry.midpoint(k, KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER) ?: return false
        return hands.y < shoulders.y
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

    private companion object {
        /** How long the frames must keep pointing at a position before it is entered, as the start gate waits. */
        const val ENTRY_MS = 500L

        /** How long the bar or standing is kept without its own rule holding. */
        const val KEEP_MS = 1_000L

        /**
         * How far under its knee a seen ankle must be, in thighs, for the shin to stand. Measured on
         * the Cindy clip with MoveNet Thunder: kneeling never put an ankle more than 0.05 thighs
         * below the knee, standing and squatting never put one less than about 0.6.
         */
        const val SHIN_UNDER_KNEE_THIGHS = 0.5f

        /** A thigh shorter than this cannot be measured against. */
        const val MIN_THIGH_PX = 1f

        /** A torso shorter than this is shoulders and hips on top of each other, not a torso. */
        const val MIN_TORSO_PX = 1f

        /** Each leg's hip, knee and ankle. */
        val LEGS = listOf(
            Triple(KP.LEFT_HIP, KP.LEFT_KNEE, KP.LEFT_ANKLE),
            Triple(KP.RIGHT_HIP, KP.RIGHT_KNEE, KP.RIGHT_ANKLE)
        )

        val NO_EVIDENCE = Frame(
            handsAboveShoulders = false,
            shinsUnderKnees = false,
            upright = false,
            torsoSeen = false
        )
    }
}
