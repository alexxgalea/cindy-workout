package com.cindy.tracker

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That an adapted session is recorded as what it was, and ranked against its own kind.
 *
 * The counting rules are tested elsewhere. What is tested here is the promise the app makes
 * about its own history: a band-assisted Cindy is never quietly filed as a strict one, never
 * takes the strict record, and never earns a rung on a ladder calibrated against a workout it
 * did not attempt — while still being a session the athlete did, on a day they trained.
 */
class VariationsTest {

    private val adaptive = CindyProfile(
        pull = PullVariant.BAND_ASSISTED_PULL_UP,
        push = PushVariant.KNEE_PUSH_UP,
        squat = SquatVariant.BOX_SQUAT
    )

    private fun attempt(
        rounds: Int,
        reps: Int = 0,
        at: Long = 1_000L,
        profile: CindyProfile? = CindyProfile.STANDARD,
        manualReps: Int = 0
    ) = Attempt(
        rounds = rounds, reps = reps, atMillis = at, durationMs = 20 * 60 * 1000L,
        profile = profile, manualReps = manualReps
    )

    // ── the profile survives a round trip ─────────────────────────────────────

    @Test
    fun `an adaptive session stores the movements it was run with`() {
        val saved = Records.decode(Records.encode(listOf(attempt(7, 12, profile = adaptive))))

        assertEquals(1, saved.size)
        assertEquals(adaptive, saved.single().profile)
        assertEquals(CindyMode.ADAPTIVE, saved.single().profile?.mode)
    }

    @Test
    fun `reps tapped in survive a round trip`() {
        val saved = Records.decode(Records.encode(listOf(attempt(3, 0, manualReps = 12))))

        assertEquals(12, saved.single().manualReps)
    }

    /**
     * History written before the choice existed was standard Cindy, because that was the only
     * thing the app did. Reading it as standard is a fact, not an assumption.
     */
    @Test
    fun `attempts written before variations existed read as standard`() {
        val v3 = "v3|8|12|1700000000000|1200000|0|150000,160000"

        val decoded = Records.decode(v3).single()

        assertEquals(CindyProfile.STANDARD, decoded.profile)
        assertEquals(8, decoded.rounds)
    }

    /**
     * The one case where guessing would be a lie.
     *
     * A movement this build does not know cannot be filed under a movement it does — that would
     * silently promote someone's assisted session into the strict record. It stays unknown, and
     * unknown is its own category.
     */
    @Test
    fun `an unrecognised movement leaves the profile unknown rather than standard`() {
        val v4 = "v4|8|0|1700000000000|1200000|0||ONE_ARM_PULL_UP|STANDARD_PUSH_UP|AIR_SQUAT|0"

        val decoded = Records.decode(v4).single()

        assertNull("not silently relabelled as standard", decoded.profile)
        assertEquals("but the session itself is still theirs", 8, decoded.rounds)
        assertNotEquals(CindyProfile.STANDARD, decoded.profile)
    }

    // ── separate records ──────────────────────────────────────────────────────

    @Test
    fun `an adaptive result never becomes the strict record`() {
        val history = listOf(
            attempt(8, at = 1L, profile = CindyProfile.STANDARD),
            attempt(20, at = 2L, profile = adaptive)
        )

        assertEquals(8, Records.bestIn(history, CindyProfile.STANDARD)?.rounds)
        assertEquals(20, Records.bestIn(history, adaptive)?.rounds)
    }

    /**
     * And not merely "standard versus the rest": two different adaptations are no more
     * comparable to each other than either is to the strict movement.
     */
    @Test
    fun `two different adaptations are separate categories`() {
        val knees = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        val box = CindyProfile(squat = SquatVariant.BOX_SQUAT)
        val history = listOf(attempt(9, at = 1L, profile = knees), attempt(14, at = 2L, profile = box))

        assertEquals(9, Records.bestIn(history, knees)?.rounds)
        assertEquals(14, Records.bestIn(history, box)?.rounds)
        assertNull(Records.bestIn(history, CindyProfile.STANDARD))
    }

    @Test
    fun `a personal record is beaten only by the same movements`() {
        val history = listOf(attempt(10, at = 1L, profile = adaptive))
        val betterAdaptive = attempt(11, at = 2L, profile = adaptive)
        val strictOfSameSize = attempt(11, at = 3L, profile = CindyProfile.STANDARD)

        assertTrue(Records.isPersonalRecord(history + betterAdaptive, betterAdaptive))
        assertTrue("first strict session sets its own record", Records.isPersonalRecord(history + strictOfSameSize, strictOfSameSize))
        assertEquals(10, Records.personalRecord(history + betterAdaptive, betterAdaptive)?.rounds)
        assertNull("nothing strict to compare against", Records.personalRecord(history + strictOfSameSize, strictOfSameSize))
    }

    // ── the ladder and the benchmark ──────────────────────────────────────────

    @Test
    fun `the strict ladder does not rank an adaptive session`() {
        assertEquals(Level.INTERMEDIATE, attempt(12).level)
        assertNull("no rung for a workout the ladder does not describe", attempt(12, profile = adaptive).level)
        assertNull(attempt(12, profile = null).level)
    }

    @Test
    fun `an adaptive session is captioned with its movements instead of a rung`() {
        assertEquals("Intermediate", attempt(12).caption)
        assertEquals(
            "Adaptive Cindy · band-assisted pull-ups · knee push-ups · box squats",
            attempt(12, profile = adaptive).caption
        )
    }

    /** Twenty-seven rounds of knee push-ups is not level with a strict twenty-seven. */
    @Test
    fun `an adaptive session never passes the benchmark`() {
        assertTrue(Records.beatsBenchmark(attempt(28)))
        assertFalse(Records.beatsBenchmark(attempt(28, profile = adaptive)))
        assertFalse(Records.beatsBenchmark(attempt(28, profile = null)))
    }

    // ── what adaptive sessions still count for ────────────────────────────────

    /**
     * The streak measures showing up, and an adaptive athlete showed up.
     *
     * Deliberate: separating the *scores* is honesty, but withholding the streak would make the
     * separation a punishment, which is the opposite of the point.
     */
    @Test
    fun `adaptive sessions count toward the streak`() {
        val zone = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 3, 10)
        fun onDay(day: Int, profile: CindyProfile?) = attempt(
            5, at = LocalDate.of(2026, 3, day).atStartOfDay(zone).toInstant().toEpochMilli(),
            profile = profile
        )

        val days = Streak.daysTrained(
            listOf(
                onDay(8, CindyProfile.STANDARD),
                onDay(9, adaptive),
                onDay(10, adaptive)
            ),
            zone
        )

        assertEquals(3, Streak.current(days, today))
    }

    // ── the picker's own memory ───────────────────────────────────────────────

    @Test
    fun `the chosen profile survives being saved and read back`() {
        assertEquals(adaptive, Variations.decode(Variations.encode(adaptive)))
        assertEquals(CindyProfile.STANDARD, Variations.decode(null))
        assertEquals(CindyProfile.STANDARD, Variations.decode("nonsense"))
    }

    /**
     * A preference is not a record: falling back here costs the athlete one visit to the picker,
     * whereas falling back in [Records] would rewrite what they did.
     */
    @Test
    fun `an unknown saved choice falls back to the standard movement`() {
        val decoded = Variations.decode("ONE_ARM_PULL_UP|KNEE_PUSH_UP|AIR_SQUAT")

        assertEquals(PullVariant.STRICT_PULL_UP, decoded.pull)
        assertEquals("the choices it does understand are kept", PushVariant.KNEE_PUSH_UP, decoded.push)
    }

    // ── labels ────────────────────────────────────────────────────────────────

    @Test
    fun `a profile names only what was changed`() {
        assertEquals("Cindy", CindyProfile.STANDARD.label())
        assertEquals(
            "Adaptive Cindy · knee push-ups",
            CindyProfile(push = PushVariant.KNEE_PUSH_UP).label()
        )
    }

    @Test
    fun `a profile knows which movements it will ask to be tapped in`() {
        assertTrue(CindyProfile.STANDARD.fullyAutomatic)
        assertTrue(adaptive.fullyAutomatic)
        assertEquals(
            listOf(Exercise.PULLUP),
            CindyProfile(pull = PullVariant.NEGATIVE_PULL_UP).manualMovements
        )
    }
}
