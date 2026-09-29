package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A frame that has not been confirmed as the athlete must not count or teach, for every
 * movement — not just pull-ups. These tests pin that contract, and the bounded grace period a
 * rep in flight survives while identity is briefly unconfirmed.
 *
 * The fixture at the centre of most of these tests is a synthetic body standing still elsewhere
 * in the frame: upright, arms hanging straight by the sides, legs straight. That shape happens to
 * read as the locked-out top of a push-up and as the standing top of a squat, so fed to the
 * engine with no gate on identity it can complete whichever rep the athlete had already started.
 * Refused, it must not.
 */
class IdentityRefusalTest {

    private var clock = 0L

    private fun WorkoutEngine.feed(
        pose: Array<Keypoint>,
        identityStable: Boolean = true,
        frames: Int = 1
    ): RepEvent {
        var last = RepEvent.NONE
        repeat(frames) {
            last = onFrame(pose, clock, identityStable)
            clock += 100
        }
        return last
    }

    private fun WorkoutEngine.doPullup(hang: Float = 170f, top: Float = 60f) {
        feed(PoseFixtures.pullup(hang), frames = 10)
        feed(PoseFixtures.pullup(top), frames = 10)
    }

    private fun WorkoutEngine.doPushup() {
        feed(PoseFixtures.pushup(175f), frames = 10)
        feed(PoseFixtures.pushup(80f), frames = 10)
        feed(PoseFixtures.pushup(175f), frames = 10)
    }

    // ── a bystander at the bottom of a rep ──────────────────────────────────

    @Test
    fun `three standing frames at the bottom of a push-up book a rep when trusted`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        e.feed(PoseFixtures.pushup(80f), frames = 10)
        e.feed(PoseFixtures.standing(), frames = 3)
        assertEquals("pins the behaviour before an identity check existed", 1, e.reps)
    }

    @Test
    fun `three standing frames at the bottom of a push-up book nothing when refused`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        e.feed(PoseFixtures.pushup(80f), frames = 10)
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 3)
        assertEquals("a refused body must not complete the athlete's rep", 0, e.reps)
    }

    @Test
    fun `three standing frames at the bottom of a squat book a rep when trusted`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        e.feed(PoseFixtures.squat(80f), frames = 10)
        e.feed(PoseFixtures.standing(), frames = 3)
        assertEquals("pins the behaviour before an identity check existed", 1, e.reps)
    }

    @Test
    fun `three standing frames at the bottom of a squat book nothing when refused`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        e.feed(PoseFixtures.squat(80f), frames = 10)
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 3)
        assertEquals("a refused body must not complete the athlete's rep", 0, e.reps)
    }

    @Test
    fun `refused frames leave the learned range unchanged`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        e.feed(PoseFixtures.pushup(80f), frames = 10)
        val before = e.learnedRange
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 5)
        assertEquals("a refused body is not evidence about the athlete's range", before, e.learnedRange, 0f)
    }

    // ── a refused gap bounded by time, not by the occlusion rule ────────────

    @Test
    fun `a refused gap under a second keeps the push-up, and the top after it counts`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        e.feed(PoseFixtures.pushup(80f), frames = 10)
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 5) // 500ms, well under 1s
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        assertEquals(1, e.reps)
    }

    @Test
    fun `a refused gap over a second abandons the push-up, but the next full cycle counts`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        e.feed(PoseFixtures.pushup(80f), frames = 10)
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 15) // 1.5s, over the limit
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        assertEquals("the abandoned climb must not count", 0, e.reps)

        e.feed(PoseFixtures.pushup(80f), frames = 10)
        e.feed(PoseFixtures.pushup(175f), frames = 10)
        assertEquals("a full cycle afterwards counts normally", 1, e.reps)
    }

    @Test
    fun `exactly a one-second refused gap still keeps the squat`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        e.feed(PoseFixtures.squat(80f), frames = 10)
        // IDENTITY_DROPOUT_MS is 1000; the gap is measured from the first refused frame, so the
        // eleventh one (ten steps of 100ms later) is the one that reads exactly 1000ms.
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 11)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        assertEquals("a gap of exactly the limit is not yet abandoned", 1, e.reps)
    }

    @Test
    fun `one frame past a one-second refused gap clears the squat`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        e.feed(PoseFixtures.squat(80f), frames = 10)
        e.feed(PoseFixtures.standing(), identityStable = false, frames = 12)
        e.feed(PoseFixtures.squat(175f), frames = 10)
        assertEquals("the twelfth consecutive refusal ends the cycle", 0, e.reps)
    }

    @Test
    fun `exactly a one-second refused gap still keeps the pull-up`() {
        val e = WorkoutEngine()
        e.feed(PoseFixtures.pullup(170f), frames = 10)
        e.feed(PoseFixtures.pullup(170f), identityStable = false, frames = 11)
        e.feed(PoseFixtures.pullup(60f), frames = 10)
        assertEquals("a gap of exactly the limit is not yet abandoned", 1, e.reps)
    }

    @Test
    fun `one frame past a one-second refused gap clears the pull-up`() {
        val e = WorkoutEngine()
        e.feed(PoseFixtures.pullup(170f), frames = 10)
        e.feed(PoseFixtures.pullup(170f), identityStable = false, frames = 12)
        e.feed(PoseFixtures.pullup(60f), frames = 10)
        assertEquals("the twelfth consecutive refusal ends the cycle", 0, e.reps)
    }

    @Test
    fun `unreadable pull-up frames still clear the cycle after eight, whatever identity says`() {
        val e = WorkoutEngine()
        e.feed(PoseFixtures.pullup(170f), frames = 10)
        // Confirmed throughout, but unreadable: the eight-frame occlusion rule is a different
        // limit from the identity gap, and this run is far short of the identity grace period.
        repeat(9) {
            val hidden = PoseFixtures.pullup(60f)
            hidden[KP.NOSE] = Keypoint(0f, 0f, 0f)
            e.feed(hidden, frames = 1)
        }
        e.feed(PoseFixtures.pullup(60f), frames = 1)
        assertEquals("the ninth consecutive blackout ends the cycle on its own terms", 0, e.reps)
    }

    // ── the squat start dwell ────────────────────────────────────────────────

    @Test
    fun `refused standing frames never complete the squat start dwell`() {
        val e = WorkoutEngine()
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        assertEquals(Exercise.SQUAT, e.exercise)
        assertTrue(e.awaitingStart)

        // Four confirmed frames (400ms) interrupted by one refused frame, repeated well past what
        // 500ms of unbroken confirmation would need: the dwell must never accumulate across the
        // interruption.
        repeat(10) {
            e.feed(PoseFixtures.standing(), frames = 4)
            e.feed(PoseFixtures.standing(), identityStable = false, frames = 1)
        }
        assertTrue("interrupted confirmation must never complete the dwell", e.awaitingStart)

        // A real, uninterrupted run finally opens the gate.
        e.feed(PoseFixtures.standing(), frames = 10)
        assertFalse("500ms of uninterrupted confirmation completes the dwell", e.awaitingStart)
    }

    // ── setup ────────────────────────────────────────────────────────────────

    @Test
    fun `refused setup frames teach no calibration`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PUSHUP)
        e.beginSetup()
        repeat(5) {
            e.onSetupFrame(PoseFixtures.pushup(175f), clock, identityStable = false)
            clock += 100
            e.onSetupFrame(PoseFixtures.pushup(80f), clock, identityStable = false)
            clock += 100
        }
        assertEquals("a refused body must not teach the calibration band", 0f, e.learnedRange, 0f)
    }

    @Test
    fun `refused hang frames teach no bar during setup`() {
        val e = WorkoutEngine(fixedExercise = Exercise.PULLUP)
        e.beginSetup()
        repeat(5) {
            e.onSetupFrame(PoseFixtures.pullup(170f), clock, identityStable = false)
            clock += 100
        }
        assertFalse("a refused hang must not establish the bar", e.barKnown)
    }
}
