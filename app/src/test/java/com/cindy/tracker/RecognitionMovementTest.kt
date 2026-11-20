package com.cindy.tracker

import com.cindy.tracker.Movement.PULL_UPS
import com.cindy.tracker.Movement.PUSH_UPS
import com.cindy.tracker.Movement.SQUATS
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which movement the athlete is doing, worked out from their position and the reps counted in it.
 *
 * Every test goes through the recogniser's one entry point, a frame at a time, and reads the
 * [Recognition] it returns. Nothing reaches into the engines it drives: which engine was fed
 * shows up as which movement got reps.
 */
class RecognitionMovementTest {

    private var recogniser = Recogniser()
    private var clock = 0L
    private var last = Recognition(Position.NONE)

    private fun hold(pose: Array<Keypoint>, forMs: Long = 1_000, stable: Boolean = true): Recognition {
        repeat((forMs / 100).toInt()) {
            last = recogniser.onFrame(pose, clock, stable)
            clock += 100
        }
        return last
    }

    private fun squatRep() {
        hold(PoseFixtures.squat(80f))
        hold(PoseFixtures.squat(175f))
    }

    private fun pushupRep() {
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    /** From a still hang: the bar is learned from it, with no setup check. */
    private fun hang() = hold(PoseFixtures.hangWithLegs(170f), forMs = 4_000)

    private fun pullupRep() {
        hold(PoseFixtures.hangWithLegs(60f))
        hold(PoseFixtures.hangWithLegs(170f))
    }

    private fun tally(m: Movement) = last.tally.getValue(m)

    // ---- Confirmation ----

    @Test
    fun `nothing is recognised before any rep`() {
        hold(PoseFixtures.pushup(175f))
        assertEquals(Position.ON_THE_FLOOR, last.position)
        assertNull(last.movement)
        assertNull(last.candidate)
    }

    @Test
    fun `push-ups are recognised at the second rep and both reps are in the tally`() {
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertNull("one rep recognises nothing", last.movement)
        assertEquals(PUSH_UPS, last.candidate)
        assertEquals(1, last.candidateReps)
        assertEquals("a rep not yet confirmed is not in a tally", 0, tally(PUSH_UPS))

        pushupRep()
        assertEquals(PUSH_UPS, last.movement)
        assertEquals(2, tally(PUSH_UPS))
        assertNull(last.candidate)

        pushupRep()
        assertEquals(3, tally(PUSH_UPS))
    }

    @Test
    fun `squats are recognised at the second rep`() {
        hold(PoseFixtures.squat(175f))
        squatRep()
        assertNull(last.movement)
        squatRep()
        assertEquals(SQUATS, last.movement)
        assertEquals(2, tally(SQUATS))
    }

    @Test
    fun `pull-ups are recognised at the second rep, with the bar learned from a still hang`() {
        hang()
        pullupRep()
        assertNull(last.movement)
        pullupRep()
        assertEquals(PULL_UPS, last.movement)
        assertEquals(2, tally(PULL_UPS))
    }

    @Test
    fun `only the engine of the position that is entered counts, so a set is one movement`() {
        hang()
        repeat(4) { pullupRep() }
        // A pull-up swings the elbows through the push-up counter's range; fed to it they would count.
        assertEquals(4, tally(PULL_UPS))
        assertEquals(0, tally(PUSH_UPS))
        assertEquals(0, tally(SQUATS))
        assertNull(last.candidate)
    }

    @Test
    fun `no position, no counting, however the athlete moves`() {
        // Another person's frames: no identity, so no position, so no engine is fed.
        repeat(6) {
            hold(PoseFixtures.squat(80f), stable = false)
            hold(PoseFixtures.squat(175f), stable = false)
        }
        assertEquals(Position.NONE, last.position)
        assertNull(last.movement)
        assertEquals(0, tally(SQUATS))
    }

    // ---- Sticky ----

    @Test
    fun `a kneeling pause in a push-up set keeps the movement and the count`() {
        hold(PoseFixtures.pushup(175f))
        repeat(3) { pushupRep() }
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 4_000)
        assertEquals(PUSH_UPS, last.movement)
        assertEquals(3, tally(PUSH_UPS))
        hold(PoseFixtures.pushup(175f))
        pushupRep()
        assertEquals("counting resumes with no fresh confirmation", 4, tally(PUSH_UPS))
    }

    @Test
    fun `standing up to rest keeps the movement, and coming back resumes counting at once`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 3_000)
        assertEquals(Position.STANDING, last.position)
        assertEquals(PUSH_UPS, last.movement)
        assertEquals(2, tally(PUSH_UPS))

        // Back to the floor, through none as the position rules say, then reps count.
        hold(PoseFixtures.pushup(175f), forMs = 2_000)
        pushupRep()
        assertEquals(3, tally(PUSH_UPS))
        assertEquals(PUSH_UPS, last.movement)
    }

    // ---- A different movement ----

    @Test
    fun `a different movement needs its own two reps`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 2_000)

        squatRep()
        assertEquals("one squat does not switch the movement", PUSH_UPS, last.movement)
        assertEquals(SQUATS, last.candidate)
        assertEquals(1, last.candidateReps)
        assertEquals(0, tally(SQUATS))

        squatRep()
        assertEquals(SQUATS, last.movement)
        assertEquals(2, tally(SQUATS))
        assertEquals("the push-ups already done stay counted", 2, tally(PUSH_UPS))
    }

    @Test
    fun `a single rep that is left before a second does not carry over to the next visit`() {
        hold(PoseFixtures.pushup(175f))
        repeat(2) { pushupRep() }
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        squatRep()
        // Back to the floor for a while, then to the squats: one more rep is only the first again.
        hold(PoseFixtures.pushup(175f), forMs = 2_000)
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        squatRep()
        assertEquals(PUSH_UPS, last.movement)
        assertEquals(1, last.candidateReps)
    }

    // ---- Getting up off the floor ----

    @Test
    fun `getting up off the floor through a crouch confirms no squats`() {
        hold(PoseFixtures.pushup(175f))
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 1_000)
        hold(PoseFixtures.squat(80f), forMs = 600)
        hold(PoseFixtures.squat(175f), forMs = 3_000)
        assertEquals(Position.STANDING, last.position)
        assertNull(last.movement)
        assertEquals(0, tally(SQUATS))
        // Lingering in the crouch until standing is entered leaves the rise out of it as a first
        // rep at most; it takes a second rep to recognise anything.
        assertTrue(last.candidateReps <= 1)
    }

    @Test
    fun `coming back to a position with the engine left at the bottom does not book the climb`() {
        // The squat engine is left at the bottom of a squat. Arriving standing again is not its top.
        hold(PoseFixtures.squat(175f))
        hold(PoseFixtures.squat(80f))
        hold(PoseFixtures.empty(), forMs = 2_000)
        assertEquals(Position.NONE, last.position)
        hold(PoseFixtures.squat(175f), forMs = 2_000)
        assertEquals(Position.STANDING, last.position)
        assertNull(last.candidate)
        assertEquals(0, tally(SQUATS))
    }

    @Test
    fun `getting up fast, the rise already under way when the feet are entered, counts nothing`() {
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 1_000)
        hold(PoseFixtures.squat(80f), forMs = 400)
        hold(PoseFixtures.squat(130f), forMs = 100)
        hold(PoseFixtures.squat(175f), forMs = 3_000)
        assertNull(last.candidate)
        assertNull(last.movement)
    }

    @Test
    fun `after getting up fast the first real squats are the first reps`() {
        hold(PoseFixtures.kneelingUp(ankleBehind = 100f), forMs = 1_000)
        hold(PoseFixtures.squat(80f), forMs = 400)
        hold(PoseFixtures.squat(175f), forMs = 1_500)
        squatRep()
        assertEquals(1, last.candidateReps)
        squatRep()
        assertEquals(SQUATS, last.movement)
        assertEquals(2, tally(SQUATS))
    }

    // ---- Variations ----

    @Test
    fun `knee push-ups are recognised under the knee variation`() {
        recogniser = Recogniser(CindyProfile(push = PushVariant.KNEE_PUSH_UP))
        hold(PoseFixtures.kneePushup(175f))
        repeat(2) {
            hold(PoseFixtures.kneePushup(80f))
            hold(PoseFixtures.kneePushup(175f))
        }
        assertEquals(Position.ON_THE_FLOOR, last.position)
        assertEquals(PUSH_UPS, last.movement)
        assertEquals(2, tally(PUSH_UPS))
    }

    @Test
    fun `band-assisted pull-ups are recognised, and strict ones are not, on the same arms`() {
        fun fourReps(profile: CindyProfile): Recognition {
            recogniser = Recogniser(profile)
            clock = 0L
            hold(PoseFixtures.hangWithLegs(120f), forMs = 4_000)
            repeat(4) {
                hold(PoseFixtures.hangWithLegs(60f), forMs = 800)
                hold(PoseFixtures.hangWithLegs(120f), forMs = 800)
            }
            return last
        }
        assertEquals(PULL_UPS, fourReps(CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP)).movement)
        assertNull(fourReps(CindyProfile()).movement)
    }

    // ---- The bar is learned, never given ----

    @Test
    fun `the bar is learned from a still hang with nothing from a setup check`() {
        // No bar is given anywhere: the recogniser has no setup input. Reps on the bar count anyway.
        hang()
        pullupRep()
        pullupRep()
        pullupRep()
        assertEquals(3, tally(PULL_UPS))
    }

    // ---- Reset ----

    @Test
    fun `reset forgets the movement, the reps and the tallies`() {
        hold(PoseFixtures.pushup(175f))
        repeat(3) { pushupRep() }
        recogniser.reset()
        val after = recogniser.onFrame(PoseFixtures.pushup(175f), clock)
        assertEquals(Recognition(Position.NONE), after)
        assertNull(after.movement)
        assertEquals(0, after.tally.getValue(PUSH_UPS))
    }
}
