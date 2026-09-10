package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The band-assisted pull-up: a relaxed bottom, and nothing else relaxed.
 *
 * The band takes enough weight that the arms may never straighten, so requiring a dead hang
 * means the reset never arms and the session scores zero with the counter working perfectly
 * behind a gate the athlete cannot open. What replaces it is the head dropping back below the
 * reset line — a torso-scaled offset the camera's viewpoint cannot flatten, and a position you
 * cannot be in at the top of a rep.
 *
 * Everything else still applies, and these tests say so: the head still has to clear the bar,
 * the hands still have to be on it, and [RepCounter] still wants the athlete's whole learned
 * travel. A relaxed bottom buys a shallow rep nothing.
 */
class AssistedPullupTest {

    /** As straight as this athlete gets, hanging in a band. Well under a dead hang. */
    private val bottom = 120f
    private val top = 60f

    private class Driver(val engine: WorkoutEngine) {
        private var clock = 0L

        fun hold(pose: Array<Keypoint>, frames: Int) = repeat(frames) {
            engine.onFrame(pose, clock)
            clock += 100
        }

        /** Long enough for the settle fallback to find the bar without a dead hang. */
        fun findBar(angle: Float) = hold(PoseFixtures.pullup(angle), frames = 35)

        fun cycles(n: Int, bottom: Float, top: Float) = repeat(n) {
            hold(PoseFixtures.pullup(top), frames = 8)
            hold(PoseFixtures.pullup(bottom), frames = 8)
        }
    }

    private fun engineFor(pull: PullVariant) =
        WorkoutEngine(fixedExercise = Exercise.PULLUP, profile = CindyProfile(pull = pull))

    @Test
    fun `a band-assisted pull-up counts without a dead hang`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        assertTrue(d.engine.barKnown)
        d.cycles(6, bottom, top)

        // The first cycle teaches the counter the athlete's range; the rest score.
        assertEquals(5, d.engine.reps)
    }

    /** The same movement, in the mode that says it is a strict pull-up. Unchanged. */
    @Test
    fun `the same reps score nothing in strict mode`() {
        val d = Driver(engineFor(PullVariant.STRICT_PULL_UP))

        d.findBar(bottom)
        d.cycles(6, bottom, top)

        assertEquals(0, d.engine.reps)
    }

    /**
     * The gate that is *not* relaxed.
     *
     * Pulling only partway, so the head never clears the bar, is not a rep in either mode. This
     * is the check that the relaxed bottom did not quietly become a relaxed rep.
     */
    @Test
    fun `a band-assisted pull-up still requires the head over the bar`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        // 95 degrees leaves the head below the bar line: a genuine partial.
        d.cycles(6, bottom, 95f)

        assertEquals(0, d.engine.reps)
    }

    /**
     * And the bar itself is still a gate: arms waving overhead away from where the bar was
     * learned do not score, assisted or not.
     */
    @Test
    fun `overhead movement away from the bar does not count`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        val before = d.engine.reps
        repeat(6) {
            for (angle in listOf(top, bottom)) {
                val offBar = PoseFixtures.pullup(angle).also { k ->
                    // Same movement, done a long way to the side of the learned bar.
                    for (i in k.indices) k[i] = Keypoint(k[i].x + 900f, k[i].y, k[i].score)
                }
                d.hold(offBar, frames = 8)
            }
        }

        assertEquals(before, d.engine.reps)
    }

    /**
     * Setting the band up must not teach a bar.
     *
     * Found on real footage: standing on a box holding the band at chest height satisfies every
     * other condition the bar used to be learned from — hands above the hips, elbows extended —
     * so the bar was fixed at the athlete's chest, and every real rep afterwards was refused with
     * "Get on the bar" with no way back, because refinement requires already passing the gate.
     */
    @Test
    fun `holding a band at chest height does not teach a bar`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.hold(PoseFixtures.bandSetup(), frames = 60)

        assertFalse("the hands are below the head, so this is not a hang", d.engine.barKnown)
    }

    /** And the bar the athlete then actually hangs from is still found normally. */
    @Test
    fun `a hang after the band setup still finds the bar`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.hold(PoseFixtures.bandSetup(), frames = 60)
        d.findBar(bottom)

        assertTrue("the real hang teaches it", d.engine.barKnown)
        d.cycles(6, bottom, top)
        assertEquals("and the reps score", 5, d.engine.reps)
    }

    // ── the row is a different movement ───────────────────────────────────────
    //
    // An inverted row satisfies every pull-up gate but one: the wrists are above the hips, the
    // bar can be learned from the hands, the head reaches the bar line and the elbow swings a
    // full range. Only the torso's direction separates the families.

    @Test
    fun `inverted rows never count as strict pull-ups`() {
        val d = Driver(engineFor(PullVariant.STRICT_PULL_UP))

        d.findBar(bottom)
        repeat(6) {
            d.hold(PoseFixtures.invertedRow(top), frames = 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames = 8)
        }

        assertEquals(0, d.engine.reps)
        assertEquals("and says which way to hang", "Hang vertically from the bar", d.engine.hint)
    }

    @Test
    fun `inverted rows never count as band-assisted pull-ups either`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        repeat(6) {
            d.hold(PoseFixtures.invertedRow(top), frames = 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames = 8)
        }

        assertEquals("relaxing the bottom does not relax which movement it is", 0, d.engine.reps)
    }

    /** A row must not teach a bar either, or it would poison the next real hang. */
    @Test
    fun `an inverted row does not establish a bar`() {
        val d = Driver(engineFor(PullVariant.STRICT_PULL_UP))

        repeat(6) {
            d.hold(PoseFixtures.invertedRow(top), frames = 8)
            d.hold(PoseFixtures.invertedRow(bottom), frames = 8)
        }

        assertFalse(d.engine.barKnown)
    }

    /**
     * The gate is on orientation, not on stillness: a wobble mid-rep is absorbed by the same
     * dropout window that already rides out an occlusion, so a real pull-up survives it.
     */
    @Test
    fun `a brief non-vertical wobble does not throw away a valid pull-up`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        d.cycles(2, bottom, top)
        val before = d.engine.reps

        // Armed at the bottom, then four unusable frames — well inside MAX_DROPOUT_FRAMES —
        // before driving to the top. The cycle is in flight across the wobble.
        d.hold(PoseFixtures.pullup(bottom), frames = 8)
        d.hold(PoseFixtures.invertedRow(bottom), frames = 4)
        d.hold(PoseFixtures.pullup(top), frames = 8)

        assertEquals("the cycle across the wobble still scores", before + 1, d.engine.reps)
    }

    // ── rep provenance ────────────────────────────────────────────────────────

    /**
     * A tapped rep counts, and is remembered as tapped.
     *
     * The score is the athlete's either way; the *claim* about how it was arrived at is the
     * app's, and it is not entitled to the stronger one.
     */
    @Test
    fun `a manual rep is recorded as manual`() {
        val engine = engineFor(PullVariant.FOOT_ASSISTED_PULL_UP)

        engine.manualRep()

        assertEquals(1, engine.reps)
        assertEquals(1, engine.manualReps)
        assertEquals(Tracking.MANUAL, engine.lastRepSource)
    }

    @Test
    fun `undoing a tapped rep takes the tap back too`() {
        val engine = engineFor(PullVariant.FOOT_ASSISTED_PULL_UP)

        engine.manualRep()
        engine.manualRep()
        engine.undoRep()

        assertEquals(1, engine.reps)
        assertEquals(1, engine.manualReps)
    }

    @Test
    fun `a rep the camera scored is not counted as manual`() {
        val d = Driver(engineFor(PullVariant.BAND_ASSISTED_PULL_UP))

        d.findBar(bottom)
        d.cycles(3, bottom, top)

        assertTrue("the camera scored at least one", d.engine.reps > 0)
        assertEquals(0, d.engine.manualReps)
        assertEquals(Tracking.AUTO, d.engine.lastRepSource)
    }
}
