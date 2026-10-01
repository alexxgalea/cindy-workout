package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiftedTest {

    private fun split(movement: Exercise, reps: Int, manual: Int = 0) =
        SetSplit(movement, ms = 1_000L, reps = reps, manualReps = manual)

    /** One full round, then [extraReps] more pull-ups in progress. */
    private fun attempt(
        profile: CindyProfile? = CindyProfile.STANDARD,
        splits: List<SetSplit> = listOf(
            split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15)
        ),
        counted: Int? = splits.sumOf { it.reps },
        untrackedMs: Long = 0L,
        manualReps: Int = 0
    ) = Attempt(
        rounds = counted?.div(30) ?: 0, reps = 0, atMillis = 0L, countedReps = counted,
        setSplits = splits, profile = profile, untrackedMs = untrackedMs, manualReps = manualReps
    )

    @Test
    fun `a standard round lifts the three shares of the body weight`() {
        val lifted = Lifted.of(attempt(), 80.0)!!

        assertEquals(listOf(Exercise.PULLUP, Exercise.PUSHUP, Exercise.SQUAT), lifted.parts.map { it.movement })
        assertEquals(5 * 0.95 * 80.0, lifted.parts[0].kg, 1e-9)
        assertEquals(10 * 0.64 * 80.0, lifted.parts[1].kg, 1e-9)
        assertEquals(15 * 0.88 * 80.0, lifted.parts[2].kg, 1e-9)
        assertEquals((5 * 0.95 + 10 * 0.64 + 15 * 0.88) * 80.0, lifted.totalKg, 1e-9)
        assertTrue(lifted.omitted.isEmpty())
        assertFalse(lifted.atLeast)
    }

    @Test
    fun `reps are summed across rounds and include the movement in progress`() {
        val splits = listOf(
            split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15),
            split(Exercise.PULLUP, 5)
        )
        // 35 banked in splits, plus 4 push-ups still running when the clock stopped.
        val lifted = Lifted.of(attempt(splits = splits, counted = 39), 70.0)!!

        assertEquals(listOf(10, 14, 15), lifted.parts.map { it.reps })
    }

    @Test
    fun `knee push-ups use their own share and their own name`() {
        val lifted = Lifted.of(attempt(profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)), 80.0)!!

        val push = lifted.parts.first { it.movement == Exercise.PUSHUP }
        assertEquals(0.49, push.share, 0.0)
        assertEquals("knee push-ups", push.label)
        assertEquals(10 * 0.49 * 80.0, push.kg, 1e-9)
    }

    @Test
    fun `heels-flat and box squats share the air squat's body fraction`() {
        for (variant in listOf(SquatVariant.AIR_SQUAT, SquatVariant.HEELS_FLAT, SquatVariant.BOX_SQUAT)) {
            val lifted = Lifted.of(attempt(profile = CindyProfile(squat = variant)), 80.0)!!
            assertEquals(variant.name, 0.88, lifted.parts.first { it.movement == Exercise.SQUAT }.share, 0.0)
        }
    }

    @Test
    fun `band-assisted pull-ups are left out by name, never guessed`() {
        val lifted = Lifted.of(
            attempt(profile = CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP)), 80.0
        )!!

        assertEquals(listOf(Exercise.PUSHUP, Exercise.SQUAT), lifted.parts.map { it.movement })
        val left = lifted.omitted.single()
        assertEquals(Exercise.PULLUP, left.movement)
        assertEquals("band-assisted pull-ups", left.label)
        assertEquals(5, left.reps)
        // The pull-ups contribute nothing to the total.
        assertEquals((10 * 0.64 + 15 * 0.88) * 80.0, lifted.totalKg, 1e-9)
        assertTrue(
            lifted.footnote(tappedIn = false)
                .contains("Band-assisted pull-ups are left out: the band's share isn't known.")
        )
    }

    @Test
    fun `every variant without a stated share is left out`() {
        val leftOut = listOf(
            CindyProfile(pull = PullVariant.INVERTED_ROW),
            CindyProfile(pull = PullVariant.FOOT_ASSISTED_PULL_UP),
            CindyProfile(pull = PullVariant.NEGATIVE_PULL_UP),
            CindyProfile(push = PushVariant.INCLINE_PUSH_UP),
            CindyProfile(squat = SquatVariant.SUPPORTED_SQUAT)
        )
        for (profile in leftOut) {
            val lifted = Lifted.of(attempt(profile = profile), 80.0)!!
            assertEquals(profile.label(), 1, lifted.omitted.size)
            assertEquals(profile.label(), 2, lifted.parts.size)
        }
    }

    @Test
    fun `a movement with no reps is not named as left out`() {
        // The pull-ups were skipped at zero: nothing was done, so nothing was omitted.
        val splits = listOf(split(Exercise.PULLUP, 0), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15))
        val lifted = Lifted.of(
            attempt(profile = CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP), splits = splits), 80.0
        )!!

        assertTrue(lifted.omitted.isEmpty())
    }

    @Test
    fun `a session of only left-out movements has nothing to show`() {
        val splits = listOf(split(Exercise.PULLUP, 5))
        val a = attempt(profile = CindyProfile(pull = PullVariant.BAND_ASSISTED_PULL_UP), splits = splits)

        assertNull(Lifted.of(a, 80.0))
        assertFalse(Lifted.measurable(a))
    }

    @Test
    fun `a lower-bound attempt says at least`() {
        val lifted = Lifted.of(attempt(untrackedMs = Records.UNTRACKED_TOLERANCE_MS), 80.0)!!

        assertTrue(lifted.atLeast)
        assertTrue(lifted.kgText().startsWith("At least "))
        assertTrue(lifted.footnote(tappedIn = false).contains("floor"))
    }

    @Test
    fun `no body weight, no tally`() {
        assertNull(Lifted.of(attempt(), 0.0))
        assertNull(Lifted.of(attempt(), -5.0))
        assertNull(Lifted.of(attempt(), Double.NaN))
        // ...but the page can still tell that a weight would unlock something.
        assertTrue(Lifted.measurable(attempt()))
    }

    @Test
    fun `no sets, no tally`() {
        // Before set times existed the record carries a total but no way to say which movement.
        val old = attempt(splits = emptyList(), counted = 30)
        // 30 counted with no splits cannot be a pull-up set in progress, so the record is refused.
        assertNull(Lifted.of(old, 80.0))
        assertFalse(Lifted.measurable(old))
    }

    @Test
    fun `an inferred tally is never lifted`() {
        assertNull(Lifted.of(attempt(counted = null), 80.0))
    }

    @Test
    fun `a session of movements this build does not know is not relabelled as standard`() {
        assertNull(Lifted.of(attempt(profile = null), 80.0))
    }

    @Test
    fun `tapped-in reps count and the footnote says they are a different claim`() {
        val splits = listOf(split(Exercise.PULLUP, 5, manual = 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15))
        val a = attempt(splits = splits, manualReps = 5)
        val lifted = Lifted.of(a, 80.0)!!

        assertEquals(5, lifted.parts.first { it.movement == Exercise.PULLUP }.reps)
        assertTrue(lifted.footnote(tappedIn = true).contains("tapped in"))
        assertFalse(lifted.footnote(tappedIn = false).contains("tapped in"))
    }

    @Test
    fun `the footnote names exactly the shares that were applied`() {
        val note = Lifted.of(attempt(profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)), 80.0)!!
            .footnote(tappedIn = false)

        assertTrue(note, note.contains("strict pull-ups 95%"))
        assertTrue(note, note.contains("knee push-ups 49%"))
        assertTrue(note, note.contains("air squats 88%"))
        assertFalse(note, note.contains("64%"))
        assertTrue(note, note.startsWith("An estimate"))
    }

    @Test
    fun `the kilograms are rounded and grouped, and say about`() {
        val lifted = Lifted(emptyList(), emptyList(), totalKg = 12_943.6, atLeast = false)
        assertEquals("About 12,940 kg", lifted.kgText())
        assertEquals("About 87 kg", lifted.copy(totalKg = 86.6).kgText())
        assertEquals("About 100 kg", lifted.copy(totalKg = 104.0).kgText())
        assertEquals("At least 12,940 kg", lifted.copy(atLeast = true).kgText())
        assertNotNull(lifted)
    }
}
