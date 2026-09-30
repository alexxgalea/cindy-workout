package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A squat done with the heels flat on the floor is a correct squat, and has to count.
 *
 * It stops higher than one up on the toes, because the heels hold the knees back, so seen from a
 * phone on the floor it travels barely more than half what the air squat asks of the knee. The
 * numbers here are the ones measured through the real engine: the shallowest bottom that still
 * counts from each camera height, and the quarter squats and partials that must never.
 *
 * Standing is 175 degrees of knee from a phone at chest height and about 145 from one on the
 * floor, which is the placement the README calls normal.
 */
class HeelsFlatSquatTest {

    private var clock = 0L

    private val flat = CindyProfile(squat = SquatVariant.HEELS_FLAT)

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10) {
        repeat(frames) { onFrame(pose, clock); clock += 100 }
    }

    /** An engine on squats alone, stood up the way the athlete is when the set begins. */
    private fun squatting(stand: Float, profile: CindyProfile = flat): WorkoutEngine {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT, profile = profile)
        e.hold(PoseFixtures.squat(stand), frames = 12)
        return e
    }

    private fun WorkoutEngine.rep(stand: Float, bottom: Float) {
        hold(PoseFixtures.squat(bottom))
        hold(PoseFixtures.squat(stand))
    }

    /** What the engine counts for one rep to each of [bottoms], starting and ending at [stand]. */
    private fun repsOf(stand: Float, bottoms: List<Float>, profile: CindyProfile = flat): Int {
        val e = squatting(stand, profile)
        bottoms.forEach { e.rep(stand, it) }
        return e.reps
    }

    private fun each(n: Int, bottom: Float) = List(n) { bottom }

    // ── what counts ───────────────────────────────────────────────────────────

    @Test
    fun `heels flat squats count from a phone at chest height`() {
        assertEquals(10, repsOf(175f, each(10, 125f)))
        assertEquals(10, repsOf(175f, each(10, 135f)))
    }

    @Test
    fun `heels flat squats count from a phone on the floor`() {
        assertEquals(10, repsOf(145f, each(10, 105f)))
    }

    @Test
    fun `the air squat refuses what a heels flat squat is counted for`() {
        // The whole reason for the choice: same body, same movement, and the standard counter
        // books none of it.
        assertEquals(0, repsOf(175f, each(10, 125f), CindyProfile.STANDARD))
        assertEquals(0, repsOf(145f, each(10, 105f), CindyProfile.STANDARD))
    }

    @Test
    fun `a full depth squat is a heels flat squat too`() {
        assertEquals(10, repsOf(175f, each(10, 80f)))
        assertEquals(10, repsOf(145f, each(10, 85f)))
    }

    @Test
    fun `from chest height the shallowest squat that counts is 135 degrees`() {
        assertEquals(10, repsOf(175f, each(10, 135f)))
        assertEquals(0, repsOf(175f, each(10, 140f)))
    }

    /**
     * The line the whole choice is tuned on. Lowering HEELS_FLAT_MIN_TRAVEL moves it: a retune
     * that stops these two agreeing is a retune that changed what counts, and should say so here.
     */
    @Test
    fun `from the floor the shallowest squat that counts is 105 degrees`() {
        assertEquals(10, repsOf(145f, each(10, 105f)))
        assertEquals(0, repsOf(145f, each(10, 110f)))
    }

    // ── what never counts ─────────────────────────────────────────────────────

    @Test
    fun `quarter squats never count`() {
        assertEquals(0, repsOf(175f, each(10, 140f)))
        assertEquals(0, repsOf(175f, each(10, 145f)))
        assertEquals(0, repsOf(145f, each(10, 120f)))
    }

    @Test
    fun `partials after heels flat squats stay refused`() {
        // Three good ones set the standard; ten that barely bend the knee never meet it.
        assertEquals(3, repsOf(175f, each(3, 120f) + each(10, 150f)))
    }

    @Test
    fun `quarter squats after deep ones stay refused`() {
        assertEquals(3, repsOf(175f, each(3, 80f) + each(10, 145f)))
    }

    // ── both styles in one session ────────────────────────────────────────────

    @Test
    fun `heels flat squats after deep ones on the toes all count`() {
        // The band a deep squat teaches is as deep as the deepest, and a counter that only armed
        // near the bottom of it would refuse every shallower rep that followed.
        for (bottom in listOf(110f, 120f, 125f)) {
            assertEquals("to $bottom", 13, repsOf(175f, each(3, 70f) + each(10, bottom)))
        }
    }

    @Test
    fun `the same from a phone on the floor`() {
        assertEquals(13, repsOf(145f, each(3, 85f) + each(10, 105f)))
    }

    @Test
    fun `alternating styles count every rep`() {
        val bottoms = List(10) { if (it % 2 == 0) 80f else 120f }
        assertEquals(10, repsOf(175f, bottoms))
    }

    // ── inside a whole Cindy ──────────────────────────────────────────────────

    private fun WorkoutEngine.doPullup() {
        hold(PoseFixtures.pullup(170f))
        hold(PoseFixtures.pullup(60f))
    }

    private fun WorkoutEngine.doPushup() {
        hold(PoseFixtures.pushup(175f))
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    @Test
    fun `a round of Cindy with heels flat squats closes`() {
        val e = WorkoutEngine(profile = flat)
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        assertEquals(Exercise.SQUAT, e.exercise)

        // Up off the floor and onto the feet, which opens the squat gate without scoring.
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(175f))
        assertEquals(0, e.reps)

        repeat(15) { e.rep(175f, 125f) }
        assertEquals(1, e.rounds)
        assertEquals(Exercise.PULLUP, e.exercise)
        assertEquals(30, e.totalReps)
    }

    @Test
    fun `the choice changes only the squat, never the other two movements`() {
        val e = WorkoutEngine(profile = flat)
        repeat(5) { e.doPullup() }
        assertEquals("pull-ups still count the same", Exercise.PUSHUP, e.exercise)
        repeat(10) { e.doPushup() }
        assertEquals(Exercise.SQUAT, e.exercise)
    }

    // ── how it is recorded ────────────────────────────────────────────────────

    @Test
    fun `heels flat squats are a counted choice, not a tapped one`() {
        assertEquals(Tracking.AUTO, SquatVariant.HEELS_FLAT.tracking)
        assertTrue(flat.fullyAutomatic)
        assertTrue(flat.manualMovements.isEmpty())
    }

    @Test
    fun `a session with heels flat squats is an Adaptive Cindy that names them`() {
        assertEquals(CindyMode.ADAPTIVE, flat.mode)
        assertFalse(flat.isStandard)
        assertEquals("heels-flat squats", flat.changedMovements())
        assertEquals("Adaptive Cindy · heels-flat squats", flat.label())

        val attempt = Attempt(rounds = 9, reps = 4, atMillis = 1_000L, profile = flat)
        assertEquals("Adaptive Cindy · heels-flat squats", attempt.caption)
        assertNull("no rung on a ladder it did not attempt", attempt.level)
    }

    @Test
    fun `the choice survives being saved and read back`() {
        assertEquals(flat, Variations.decode(Variations.encode(flat)))

        val saved = Records.decode(
            Records.encode(listOf(Attempt(rounds = 9, reps = 4, atMillis = 1_000L, profile = flat)))
        )
        assertEquals(flat, saved.single().profile)
    }

    @Test
    fun `heels flat sessions are ranked against each other and not against air squats`() {
        val history = listOf(
            Attempt(rounds = 12, reps = 0, atMillis = 1L, profile = CindyProfile.STANDARD),
            Attempt(rounds = 9, reps = 0, atMillis = 2L, profile = flat)
        )
        assertEquals(9, Records.bestIn(history, flat)?.rounds)
        assertEquals(12, Records.bestIn(history, CindyProfile.STANDARD)?.rounds)
    }
}
