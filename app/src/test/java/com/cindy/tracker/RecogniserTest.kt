package com.cindy.tracker

import com.cindy.tracker.Position.NONE
import com.cindy.tracker.Position.ON_THE_BAR
import com.cindy.tracker.Position.ON_THE_FLOOR
import com.cindy.tracker.Position.STANDING
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where the athlete's body is, worked out from the frames alone.
 *
 * Every test goes through the recogniser's one entry point, a frame at a time, and reads the
 * [Position] it returns. Nothing here reaches into its dwell or gap timers: a timer that is wrong
 * shows up as a position that arrives early, late or never.
 */
class RecogniserTest {

    private var recogniser = Recogniser()
    private var clock = 0L

    /** The position after every frame fed so far, in order. */
    private val track = mutableListOf<Position>()

    /** The positions the athlete was read in, each run of the same one written once. */
    private fun runs(): List<Position> = track.filterIndexed { i, p -> i == 0 || p != track[i - 1] }

    /** Feeds [forMs] of [pose], one frame every [stepMs], and returns where the athlete is after it. */
    private fun hold(
        pose: Array<Keypoint>,
        forMs: Long = 1_000,
        stepMs: Long = 100,
        stable: Boolean = true
    ): Position {
        repeat((forMs / stepMs).toInt()) {
            track += recogniser.onFrame(pose, clock, stable).position
            clock += stepMs
        }
        return track.last()
    }

    /** Forgets what was fed so far, so a test can look only at what comes next. */
    private fun startLooking() = track.clear()

    private fun Array<Keypoint>.without(vararg joints: Int): Array<Keypoint> =
        copyOf().also { body -> joints.forEach { body[it] = Keypoint(0f, 0f, 0f) } }

    private fun Array<Keypoint>.with(joint: Int, x: Float, y: Float): Array<Keypoint> =
        copyOf().also { body -> body[joint] = Keypoint(x, y, 0.9f) }

    private val ankles = intArrayOf(KP.LEFT_ANKLE, KP.RIGHT_ANKLE)
    private val wrists = intArrayOf(KP.LEFT_WRIST, KP.RIGHT_WRIST)
    private val nobody = PoseFixtures.empty()

    // ---- The fixtures that matter are the ones today's tests get wrong ----

    @Test
    fun `kneeling up and a head-on plank both read as standing to today's posture test`() {
        // The premise of the whole module: if these did not read as standing there would be
        // nothing to protect, and a pass below would prove nothing.
        assertTrue(PoseGeometry.standing(PoseFixtures.kneelingUp(ankleBehind = 100f)))
        assertTrue(PoseGeometry.standing(PoseFixtures.headOnPlank()))
    }

    // ---- On the bar ----

    @Test
    fun `a hang is on the bar, not standing, though the legs hang straight below`() {
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f)))
        assertEquals(listOf(NONE, ON_THE_BAR), runs())
    }

    @Test
    fun `a pull-up with no legs in frame is on the bar`() {
        assertEquals(ON_THE_BAR, hold(PoseFixtures.pullup(170f)))
    }

    @Test
    fun `a gap under a second keeps the bar, and a longer one leaves it for none`() {
        hold(PoseFixtures.hangWithLegs(170f))
        startLooking()
        assertEquals(ON_THE_BAR, hold(nobody, forMs = 900))
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f)))
        assertEquals(listOf(ON_THE_BAR), runs())

        assertEquals(NONE, hold(nobody, forMs = 1_500))
    }

    @Test
    fun `a hang that loses its hands for a moment does not turn into standing`() {
        hold(PoseFixtures.hangWithLegs(170f))
        startLooking()
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f).without(*wrists), forMs = 900))
        assertEquals(listOf(ON_THE_BAR), runs())
    }

    // ---- Standing ----

    @Test
    fun `standing on the feet is standing`() {
        assertEquals(STANDING, hold(PoseFixtures.squat(175f)))
    }

    @Test
    fun `the leaning bottom of a squat stays standing`() {
        hold(PoseFixtures.squat(175f))
        startLooking()
        assertEquals(STANDING, hold(PoseFixtures.leaningSquat(90f), forMs = 3_000))
        assertEquals(listOf(STANDING), runs())
    }

    @Test
    fun `standing is refused while no shin is seen`() {
        hold(PoseFixtures.squat(175f).without(*ankles), forMs = 3_000)
        assertFalse(STANDING in track)
    }

    @Test
    fun `standing is refused while one seen shin does not stand, though the other does`() {
        // Half kneeling: one foot flat under the knee, the other shin along the floor.
        val halfKneeling = PoseFixtures.squat(175f).with(KP.RIGHT_ANKLE, 40f, 5f)
        hold(halfKneeling, forMs = 3_000)
        assertFalse(STANDING in track)
    }

    @Test
    fun `a seen shin that cannot be measured does not stand`() {
        // The left knee and ankle are seen but the left hip is not, so nothing measures that
        // thigh. The right leg stands and the torso is upright, but a leg that cannot be judged
        // is not permission.
        hold(PoseFixtures.squat(175f).without(KP.LEFT_HIP), forMs = 3_000)
        assertFalse(STANDING in track)
    }

    @Test
    fun `a shin stands under its knee from half a thigh down, and not from a little less`() {
        // The thigh in the squat fixture is 100 px at every angle; the ankle is dropped to a fixed
        // distance under the knee on both sides.
        fun ankleDrop(px: Float) = PoseFixtures.squat(175f)
            .with(KP.LEFT_ANKLE, -10f, px)
            .with(KP.RIGHT_ANKLE, 10f, px)

        assertEquals(STANDING, hold(ankleDrop(52f)))
        recogniser = Recogniser()
        assertEquals(ON_THE_FLOOR, hold(ankleDrop(48f)))
    }

    @Test
    fun `a gap under a second keeps standing, and a longer one leaves it for none`() {
        hold(PoseFixtures.squat(175f))
        startLooking()
        assertEquals(STANDING, hold(nobody, forMs = 900))
        assertEquals(STANDING, hold(PoseFixtures.squat(175f)))
        assertEquals(listOf(STANDING), runs())

        assertEquals(NONE, hold(nobody, forMs = 1_500))
    }

    // ---- On the floor ----

    @Test
    fun `kneeling up with the ankles seen behind the knees is on the floor, never standing`() {
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.kneelingUp(ankleBehind = 100f)))
        assertEquals(listOf(NONE, ON_THE_FLOOR), runs())
    }

    @Test
    fun `kneeling up with the ankles seen beside the knees is on the floor, never standing`() {
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.kneelingUp(ankleBehind = 0f)))
        assertEquals(listOf(NONE, ON_THE_FLOOR), runs())
    }

    @Test
    fun `a head-on plank is on the floor though the torso looks upright`() {
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.headOnPlank()))
        assertEquals(listOf(NONE, ON_THE_FLOOR), runs())
    }

    @Test
    fun `a plank seen from the side, with and without the legs, is on the floor`() {
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.onTheFloor()))
        recogniser = Recogniser()
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.pushup(170f)))
    }

    @Test
    fun `the floor is kept until another position is entered`() {
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f))
        assertEquals(ON_THE_FLOOR, hold(nobody, forMs = 5_000))
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.pushup(80f)))
    }

    @Test
    fun `standing up off the floor is standing after half a second on the feet`() {
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f))
        assertEquals(ON_THE_FLOOR, hold(PoseFixtures.squat(175f), forMs = 500))
        assertEquals(STANDING, hold(PoseFixtures.squat(175f), forMs = 100))
        assertEquals(listOf(NONE, ON_THE_FLOOR, STANDING), runs())
    }

    @Test
    fun `reaching the bar from the floor is on the bar`() {
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f))
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f)))
    }

    // ---- Leaving one position for another goes through none ----

    @Test
    fun `standing never turns straight into the floor`() {
        hold(PoseFixtures.squat(175f))
        startLooking()
        // The legs leave the picture, the upright body stays: the floor's own test now holds.
        hold(PoseFixtures.squat(175f).without(*ankles), forMs = 4_000)
        assertEquals(listOf(STANDING, NONE, ON_THE_FLOOR), runs())
    }

    @Test
    fun `the bar never turns straight into standing`() {
        hold(PoseFixtures.hangWithLegs(170f))
        startLooking()
        hold(PoseFixtures.hangWithLegs(170f).without(*wrists), forMs = 4_000)
        assertEquals(listOf(ON_THE_BAR, NONE, STANDING), runs())
    }

    @Test
    fun `the bar never turns straight into the floor`() {
        hold(PoseFixtures.hangWithLegs(170f))
        startLooking()
        hold(PoseFixtures.pullup(170f).without(*wrists), forMs = 4_000)
        assertEquals(listOf(ON_THE_BAR, NONE, ON_THE_FLOOR), runs())
    }

    // ---- Entering takes half a second ----

    @Test
    fun `a position is entered on the frame that completes half a second`() {
        assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 500))
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f), forMs = 100))
    }

    @Test
    fun `half a second is half a second at any frame rate`() {
        for (stepMs in listOf(33L, 50L, 125L)) {
            recogniser = Recogniser()
            track.clear()
            clock = 0L
            hold(PoseFixtures.hangWithLegs(170f), forMs = 2_000, stepMs = stepMs)
            val enteredAt = track.indexOf(ON_THE_BAR) * stepMs
            assertTrue("$stepMs ms frames entered at $enteredAt ms", enteredAt in 500 until 500 + stepMs)
        }
    }

    @Test
    fun `a position held for less than half a second is ignored, however often it comes back`() {
        repeat(5) {
            assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 400))
            hold(nobody, forMs = 100)
        }
        assertFalse(ON_THE_BAR in track)
    }

    // ---- Identity ----

    @Test
    fun `an unstable identity never enters a position`() {
        assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 3_000, stable = false))
        assertEquals(NONE, hold(PoseFixtures.squat(175f), forMs = 3_000, stable = false))
        assertEquals(NONE, hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 3_000, stable = false))
        assertEquals(setOf(NONE), track.toSet())
    }

    @Test
    fun `an unstable frame breaks the half second that was building`() {
        hold(PoseFixtures.hangWithLegs(170f), forMs = 300)
        hold(PoseFixtures.hangWithLegs(170f), forMs = 100, stable = false)
        assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 300))
    }

    @Test
    fun `an unstable identity counts towards leaving the bar and standing`() {
        hold(PoseFixtures.hangWithLegs(170f))
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f), forMs = 900, stable = false))
        assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 300, stable = false))

        recogniser = Recogniser()
        hold(PoseFixtures.squat(175f))
        assertEquals(NONE, hold(PoseFixtures.squat(175f), forMs = 1_500, stable = false))
    }

    // ---- Reset ----

    @Test
    fun `reset forgets the position and the half second that was building`() {
        hold(PoseFixtures.hangWithLegs(170f))
        recogniser.reset()
        assertEquals(NONE, recogniser.onFrame(PoseFixtures.hangWithLegs(170f), clock).position)
        clock += 100
        assertEquals(NONE, hold(PoseFixtures.hangWithLegs(170f), forMs = 400))
        assertEquals(ON_THE_BAR, hold(PoseFixtures.hangWithLegs(170f), forMs = 100))
    }
}
