package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * An air-squat session that notices heels-flat squats and goes over to counting them.
 *
 * The rule under test is one sentence: when three reps in a block are ones only the heels-flat
 * counter accepted, it takes over, and the count is brought up to what the athlete has really
 * done. Everything here is a way that could go wrong by one rep, or by a whole movement, or by
 * quietly relabelling a session that was fine: crediting a rep twice, losing one, switching for
 * someone who was squatting to full depth, or switching at all when it was never asked for.
 *
 * Standing is 175 degrees of knee from a phone at chest height and about 145 from one on the
 * floor, the same placements [HeelsFlatSquatTest] measures against.
 */
class SmartSquatTest {

    private var clock = 0L

    private fun WorkoutEngine.hold(pose: Array<Keypoint>, frames: Int = 10): List<RepEvent> {
        val events = mutableListOf<RepEvent>()
        repeat(frames) {
            val e = onFrame(pose, clock)
            if (e != RepEvent.NONE) events += e
            clock += 100
        }
        return events
    }

    /** A squat engine with smart counting on, stood up the way the athlete is at the start. */
    private fun smart(stand: Float, profile: CindyProfile = CindyProfile.STANDARD): WorkoutEngine {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT, profile = profile, smartSquats = true)
        e.hold(PoseFixtures.squat(stand), frames = 12)
        return e
    }

    /** One rep to [bottom] and back to [stand], and the events it produced. */
    private fun WorkoutEngine.rep(stand: Float, bottom: Float): List<RepEvent> =
        hold(PoseFixtures.squat(bottom)) + hold(PoseFixtures.squat(stand))

    private fun WorkoutEngine.reps(stand: Float, bottoms: List<Float>) =
        bottoms.forEach { rep(stand, it) }

    private fun each(n: Int, bottom: Float) = List(n) { bottom }

    // ── switching ─────────────────────────────────────────────────────────────

    @Test
    fun `nothing switches unless smart counting was asked for`() {
        val e = WorkoutEngine(fixedExercise = Exercise.SQUAT)
        e.hold(PoseFixtures.squat(175f), frames = 12)
        e.reps(175f, each(10, 125f))
        assertEquals("the air squat counts none of it, as it always has", 0, e.reps)
        assertFalse(e.heelsFlatSpotted)
    }

    @Test
    fun `the third heels flat squat switches and credits all three`() {
        val e = smart(175f)
        e.rep(175f, 125f)
        e.rep(175f, 125f)
        assertEquals("two is not enough", 0, e.reps)
        assertFalse(e.heelsFlatSpotted)

        val events = e.rep(175f, 125f)

        assertTrue(e.heelsFlatSpotted)
        assertEquals("the three that caused it are counted", 3, e.reps)
        assertEquals("said as one rep, at the number reached", listOf(RepEvent.REP), events)
        assertEquals(3, e.repsAtLastEvent)
    }

    @Test
    fun `what was chosen is never rewritten, only what was counted`() {
        val declared = CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP)
        val e = smart(175f, declared)
        assertEquals("before: counted as chosen", declared, e.countedProfile)

        e.reps(175f, each(3, 125f))

        assertEquals("the choice stands", declared, e.profile)
        assertEquals(
            "the count is filed as heels flat, everything else as chosen",
            declared.copy(squat = SquatVariant.HEELS_FLAT), e.countedProfile
        )
    }

    @Test
    fun `it keeps counting every squat after the switch`() {
        val e = smart(175f)
        e.reps(175f, each(10, 125f))
        assertEquals(10, e.reps)
    }

    @Test
    fun `from a phone on the floor`() {
        val e = smart(145f)
        e.reps(145f, each(10, 105f))
        assertEquals(10, e.reps)
        assertTrue(e.heelsFlatSpotted)
    }

    // ── both styles ───────────────────────────────────────────────────────────

    @Test
    fun `the heels flat reps need not be consecutive`() {
        // Deep, flat, deep, flat, ...: the flat ones are the pending ones, so the third of them
        // is the sixth rep, and the three deep ones before it are credited along with them.
        val e = smart(175f)
        e.reps(175f, List(10) { if (it % 2 == 0) 80f else 120f })
        assertTrue(e.heelsFlatSpotted)
        assertEquals(10, e.reps)
    }

    @Test
    fun `heels flat squats after deep ones on the toes are all counted`() {
        val e = smart(175f)
        e.reps(175f, each(3, 70f) + each(10, 120f))
        assertEquals("three deep, then ten heels flat", 13, e.reps)
        assertTrue(e.heelsFlatSpotted)
    }

    /**
     * The case time windows got wrong. The air-squat counter books an ascent that never quite
     * stood a little after the heels-flat counter books it, and matching the two by time took
     * that for a second rep: this session came out at 11.
     */
    @Test
    fun `a rep the two counters book at different moments is credited once`() {
        val e = smart(145f)
        e.reps(145f, each(3, 85f))
        repeat(2) {
            e.hold(PoseFixtures.squat(100f))
            e.hold(PoseFixtures.squat(130f))
        }
        e.hold(PoseFixtures.squat(145f))
        e.reps(145f, each(5, 105f))
        assertEquals("three deep, two that stopped short of standing, five heels flat", 10, e.reps)
    }

    // ── what never switches ───────────────────────────────────────────────────

    @Test
    fun `full depth squats never switch, and count as the air squat always did`() {
        val e = smart(175f)
        e.reps(175f, each(10, 80f))
        assertEquals(10, e.reps)
        assertFalse(e.heelsFlatSpotted)
        assertEquals(CindyProfile.STANDARD, e.countedProfile)
    }

    @Test
    fun `quarter squats never switch`() {
        val chest = smart(175f)
        chest.reps(175f, each(10, 140f))
        assertEquals(0, chest.reps)
        assertFalse(chest.heelsFlatSpotted)

        val floor = smart(145f)
        floor.reps(145f, each(10, 120f))
        assertEquals(0, floor.reps)
        assertFalse(floor.heelsFlatSpotted)
    }

    @Test
    fun `a few deep squats and then quarter squats do not switch`() {
        val e = smart(175f)
        e.reps(175f, each(3, 80f) + each(10, 145f))
        assertEquals(3, e.reps)
        assertFalse(e.heelsFlatSpotted)
    }

    /**
     * The trade this mode makes, pinned so that changing it is a decision.
     *
     * A knee angle cannot tell a tired squat from a heels-flat one that travels the same, so
     * anything that closes the knee 35 degrees or more counts as one, and three of them after a
     * set of deep squats switch the session. That is the permissive choice the feature is built
     * on, and the reason it is a setting that is off until real sessions show it is right.
     */
    @Test
    fun `tired squats that stop short of full depth are taken for heels flat ones`() {
        val e = smart(175f)
        e.reps(175f, each(5, 80f))
        assertFalse(e.heelsFlatSpotted)

        e.reps(175f, each(3, 130f))

        assertTrue(e.heelsFlatSpotted)
        assertEquals(8, e.reps)
        assertEquals(SquatVariant.HEELS_FLAT, e.countedProfile.squat)
    }

    @Test
    fun `it stays out of a choice the athlete already made`() {
        val flat = smart(175f, CindyProfile(squat = SquatVariant.HEELS_FLAT))
        flat.reps(175f, each(10, 125f))
        assertEquals("counted as chosen from the first rep", 10, flat.reps)
        assertFalse("there is nothing to spot", flat.heelsFlatSpotted)

        for (variant in listOf(SquatVariant.BOX_SQUAT, SquatVariant.SUPPORTED_SQUAT)) {
            val e = smart(175f, CindyProfile(squat = variant))
            e.reps(175f, each(10, 125f))
            assertEquals(variant.name, 0, e.reps)
            assertFalse(variant.name, e.heelsFlatSpotted)
        }
    }

    // ── taps, takebacks and targets ───────────────────────────────────────────

    @Test
    fun `a rep tapped in is never credited twice`() {
        val e = smart(175f)
        e.reps(175f, each(2, 125f))
        e.manualRep()
        assertEquals(1, e.reps)

        e.reps(175f, each(3, 125f))

        // Two before the tap, the tap, three after: six done, and four counted. A tap drops what
        // was pending, so the two before it are not credited. The count errs low, never high.
        assertEquals(4, e.reps)
        assertTrue(e.heelsFlatSpotted)
    }

    @Test
    fun `taking a rep back forgets what was pending`() {
        val e = WorkoutEngine(smartSquats = true)
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(175f))

        e.reps(175f, each(2, 125f))
        e.rep(175f, 80f)
        assertEquals("one full squat counted, two heels flat pending", 1, e.reps)

        e.undoRep()
        assertEquals(0, e.reps)

        // Two more would have made four pending, and switched, if the two from before the
        // takeback were still being held against them. (A takeback re-arms the air-squat counter,
        // as it always has, so the first rep after it can be counted both ways; nothing here
        // depends on that, only on how long it takes to reach three afterwards.)
        e.reps(175f, each(2, 125f))
        assertFalse("what was pending before the takeback is forgotten", e.heelsFlatSpotted)

        e.reps(175f, each(2, 125f))
        assertTrue("and three counted since the takeback switch it as usual", e.heelsFlatSpotted)
    }

    @Test
    fun `recalibrating keeps what was pending, because those reps happened`() {
        val e = smart(175f)
        e.reps(175f, each(2, 125f))

        // A pause and a resume, a flipped camera and a knocked phone all do this.
        e.recalibrate()
        e.hold(PoseFixtures.squat(175f), frames = 12)
        e.rep(175f, 125f)

        assertTrue(e.heelsFlatSpotted)
        assertEquals("the two before the pause are credited with the one after", 3, e.reps)
    }

    @Test
    fun `the credit never passes the target of the squats`() {
        val e = WorkoutEngine(smartSquats = true)
        repeat(5) { e.doPullup() }
        repeat(10) { e.doPushup() }
        e.hold(PoseFixtures.onTheFloor())
        e.hold(PoseFixtures.squat(175f))

        repeat(13) { e.manualRep() }
        assertEquals(13, e.reps)

        // Thirteen tapped and three seen would be sixteen squats in a round of fifteen.
        val last = e.rep(175f, 125f) + e.rep(175f, 125f) + e.rep(175f, 125f)

        assertTrue(last.contains(RepEvent.ROUND_DONE))
        assertEquals(1, e.rounds)
        assertEquals(30, e.totalReps)
    }

    // ── the session ───────────────────────────────────────────────────────────

    private fun WorkoutEngine.doPullup() {
        hold(PoseFixtures.pullup(170f))
        hold(PoseFixtures.pullup(60f))
    }

    private fun WorkoutEngine.doPushup() {
        hold(PoseFixtures.pushup(175f))
        hold(PoseFixtures.pushup(80f))
        hold(PoseFixtures.pushup(175f))
    }

    private fun WorkoutEngine.upToSquats() {
        repeat(5) { doPullup() }
        repeat(10) { doPushup() }
        hold(PoseFixtures.onTheFloor())
        hold(PoseFixtures.squat(175f))
    }

    @Test
    fun `a round of ordinary squats is the same with smart counting on`() {
        val e = WorkoutEngine(smartSquats = true)
        e.upToSquats()
        e.reps(175f, each(15, 80f))
        assertEquals(1, e.rounds)
        assertEquals(30, e.totalReps)
        assertFalse(e.heelsFlatSpotted)
    }

    @Test
    fun `once switched it counts from the first rep of every round`() {
        val e = WorkoutEngine(smartSquats = true)
        e.upToSquats()
        e.reps(175f, each(15, 125f))
        assertEquals(1, e.rounds)
        assertTrue(e.heelsFlatSpotted)

        e.upToSquats()
        e.rep(175f, 125f)
        assertEquals("the first heels flat squat of round two already counts", 1, e.reps)

        e.reps(175f, each(14, 125f))
        assertEquals(2, e.rounds)
        assertEquals(60, e.totalReps)
    }

    @Test
    fun `recalibrating keeps the switch and forgets the band`() {
        val e = WorkoutEngine(smartSquats = true)
        e.upToSquats()
        e.reps(175f, each(6, 125f))
        assertTrue(e.heelsFlatSpotted)

        e.recalibrate()

        assertTrue("what the athlete does with their heels is not a matter of where the phone is", e.heelsFlatSpotted)
        assertEquals(6, e.reps)
        assertEquals(0f, e.learnedRange, 0.001f)
    }

    @Test
    fun `a reset ends it`() {
        val e = WorkoutEngine(smartSquats = true)
        e.upToSquats()
        e.reps(175f, each(6, 125f))
        assertTrue(e.heelsFlatSpotted)

        e.reset()

        assertFalse(e.heelsFlatSpotted)
        assertEquals(CindyProfile.STANDARD, e.countedProfile)
        assertEquals(Exercise.PULLUP, e.exercise)
    }
}
