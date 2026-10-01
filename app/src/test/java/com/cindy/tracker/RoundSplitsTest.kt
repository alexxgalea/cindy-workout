package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RoundSplitsTest {

    private fun set(movement: Exercise, ms: Long, reps: Int = movement.target, manual: Int = 0) =
        SetSplit(movement, ms, reps, manual)

    /** One round's three sets, in order, summing to the times given. */
    private fun round(pull: Long, push: Long, squat: Long) = listOf(
        set(Exercise.PULLUP, pull), set(Exercise.PUSHUP, push), set(Exercise.SQUAT, squat)
    )

    private fun attempt(
        splits: List<Long>,
        sets: List<SetSplit> = emptyList(),
        durationMs: Long = splits.sum(),
        counted: Int? = splits.size * 30,
        at: Long = 1_000L,
        profile: CindyProfile? = CindyProfile.STANDARD
    ) = Attempt(
        rounds = splits.size, reps = 0, atMillis = at, durationMs = durationMs,
        roundSplitsMs = splits, setSplits = sets, countedReps = counted, profile = profile
    )

    // ── the bars ────────────────────────────────────────────────────────────────

    @Test
    fun `a round whose sets are in order and add up is broken down by movement`() {
        val a = attempt(listOf(168_000L), round(41_000L, 52_000L, 75_000L))

        val split = RoundSplits.of(a)!!

        assertEquals(listOf(41_000L, 52_000L, 75_000L), split.bars.single().sets)
        assertTrue(split.hasBreakdown)
    }

    @Test
    fun `a round with no set times is a plain bar`() {
        val split = RoundSplits.of(attempt(listOf(168_000L, 170_000L)))!!

        assertEquals(listOf(null, null), split.bars.map { it.sets })
        assertFalse(split.hasBreakdown)
    }

    @Test
    fun `a misordered round falls back to a plain bar without touching its neighbours`() {
        val sets = round(10_000L, 20_000L, 30_000L) +
            listOf(set(Exercise.PUSHUP, 10_000L), set(Exercise.PULLUP, 20_000L), set(Exercise.SQUAT, 30_000L)) +
            round(10_000L, 20_000L, 30_000L)
        val a = attempt(listOf(60_000L, 60_000L, 60_000L), sets)

        val bars = RoundSplits.of(a)!!.bars

        assertNotNull(bars[0].sets)
        assertNull(bars[1].sets)
        assertNotNull(bars[2].sets)
    }

    @Test
    fun `a round missing some of its sets falls back to a plain bar`() {
        val a = attempt(listOf(60_000L, 60_000L), round(10_000L, 20_000L, 30_000L) + set(Exercise.PULLUP, 5_000L))

        assertEquals(listOf(true, false), RoundSplits.of(a)!!.bars.map { it.sets != null })
    }

    @Test
    fun `sets that do not add up to the round are not believed`() {
        val a = attempt(listOf(120_000L), round(10_000L, 20_000L, 30_000L))

        assertNull(RoundSplits.of(a)!!.bars.single().sets)
    }

    @Test
    fun `a round that skipped a movement still has its breakdown`() {
        val sets = listOf(
            set(Exercise.PULLUP, 10_000L), set(Exercise.PUSHUP, 12_000L, reps = 4), set(Exercise.SQUAT, 30_000L)
        )

        val bar = RoundSplits.of(attempt(listOf(52_000L), sets, counted = 24))!!.bars.single()

        assertEquals(listOf(10_000L, 12_000L, 30_000L), bar.sets)
    }

    @Test
    fun `a round with a tapped in set says so`() {
        val sets = listOf(
            set(Exercise.PULLUP, 10_000L, manual = 2), set(Exercise.PUSHUP, 20_000L), set(Exercise.SQUAT, 30_000L)
        )

        assertTrue(RoundSplits.of(attempt(listOf(60_000L), sets))!!.bars.single().byHand)
    }

    @Test
    fun `no complete round is no chart`() {
        assertNull(RoundSplits.of(attempt(emptyList(), durationMs = 90_000L)))
    }

    @Test
    fun `the fastest round is the first of the shortest, and the average covers finished rounds only`() {
        val a = attempt(listOf(170_000L, 131_000L, 131_000L, 200_000L), durationMs = 800_000L)

        val split = RoundSplits.of(a)!!

        assertEquals(1, split.fastest)
        assertEquals(158_000L, split.averageMs)
    }

    // ── the round still going ───────────────────────────────────────────────────

    @Test
    fun `the round in progress is last, with its time so far and the reps banked in it`() {
        // Two rounds, then 5 pull-ups and 3 of 10 push-ups of the third.
        val sets = round(40_000L, 50_000L, 70_000L) + round(40_000L, 50_000L, 70_000L) +
            set(Exercise.PULLUP, 38_000L)
        val a = attempt(listOf(160_000L, 160_000L), sets, durationMs = 400_000L, counted = 68)

        val open = RoundSplits.of(a)!!.bars.last()

        assertTrue(open.unfinished)
        assertEquals(3, open.round)
        assertEquals(80_000L, open.ms)
        assertEquals(listOf(38_000L), open.sets)
        assertEquals(8, open.reps)
    }

    @Test
    fun `an unfinished round with no counted total keeps its time but not its reps`() {
        val a = attempt(listOf(160_000L), round(40_000L, 50_000L, 70_000L), durationMs = 200_000L, counted = null)

        val open = RoundSplits.of(a)!!.bars.last()

        assertTrue(open.unfinished)
        assertEquals(40_000L, open.ms)
        assertNull(open.reps)
    }

    @Test
    fun `an unfinished round whose record does not add up reads no reps`() {
        // 40 counted reps cannot be one round of 30 plus a movement still under its target.
        val a = attempt(listOf(160_000L), round(40_000L, 50_000L, 70_000L), durationMs = 200_000L, counted = 80)

        assertNull(RoundSplits.of(a)!!.bars.last().reps)
    }

    @Test
    fun `a sliver of clock after the last round is not a round in progress`() {
        val a = attempt(listOf(160_000L), durationMs = 160_400L)

        assertFalse(RoundSplits.of(a)!!.hasUnfinished)
    }

    @Test
    fun `an unfinished round with no sets banked yet reads its reps from the movement under way`() {
        val a = attempt(listOf(160_000L), round(40_000L, 50_000L, 70_000L), durationMs = 190_000L, counted = 32)

        val open = RoundSplits.of(a)!!.bars.last()

        assertEquals(emptyList<Long>(), open.sets)
        assertEquals(2, open.reps)
    }

    @Test
    fun `an unfinished round of a lower bound score is a floor`() {
        val sets = round(40_000L, 50_000L, 70_000L) + set(Exercise.PULLUP, 38_000L)
        val a = attempt(listOf(160_000L), sets, durationMs = 240_000L, counted = 36)
            .copy(untrackedMs = Records.UNTRACKED_TOLERANCE_MS)

        val open = RoundSplits.of(a)!!.bars.last()

        assertTrue(open.atLeast)
        assertEquals(6, open.reps)
        assertTrue(readout(a, 1).detail.startsWith("at least 6 of 30 reps"))
    }

    @Test
    fun `an unfinished round of a trusted score is not a floor`() {
        val sets = round(40_000L, 50_000L, 70_000L) + set(Exercise.PULLUP, 38_000L)
        val a = attempt(listOf(160_000L), sets, durationMs = 240_000L, counted = 36)

        assertFalse(RoundSplits.of(a)!!.bars.last().atLeast)
        assertTrue(readout(a, 1).detail.startsWith("6 of 30 reps"))
    }

    @Test
    fun `a lower bound with no reps to quote does not claim a floor`() {
        val a = attempt(listOf(160_000L), durationMs = 240_000L, counted = null)
            .copy(untrackedMs = Records.UNTRACKED_TOLERANCE_MS)

        assertFalse(RoundSplits.of(a)!!.bars.last().atLeast)
    }

    // ── the comparison ──────────────────────────────────────────────────────────

    @Test
    fun `the reference is the comparison's split at the same round, null past its last`() {
        val a = attempt(listOf(160_000L, 150_000L, 140_000L))
        val ref = attempt(listOf(170_000L, 145_000L))

        assertEquals(listOf<Long?>(170_000L, 145_000L, null), RoundSplits.reference(RoundSplits.of(a)!!, ref))
    }

    @Test
    fun `the unfinished round has no reference`() {
        val a = attempt(listOf(160_000L), durationMs = 200_000L)
        val ref = attempt(listOf(170_000L, 145_000L))

        assertEquals(listOf<Long?>(170_000L, null), RoundSplits.reference(RoundSplits.of(a)!!, ref))
    }

    @Test
    fun `no comparison is no reference`() {
        val a = attempt(listOf(160_000L))

        assertEquals(listOf<Long?>(null), RoundSplits.reference(RoundSplits.of(a)!!, null))
    }

    // ── the words ───────────────────────────────────────────────────────────────

    private fun readout(a: Attempt, selected: Int?, ref: Attempt? = null, kind: Comparisons.Kind? = null) =
        RoundSplits.readout(a, RoundSplits.of(a)!!, selected, ref, kind)

    @Test
    fun `nothing selected names the fastest round and the average`() {
        val a = attempt(listOf(171_000L, 131_000L, 211_000L), durationMs = 513_000L)

        assertEquals("Fastest: round 2 at 2:11 · average 2:51", readout(a, null).title)
    }

    @Test
    fun `a single round has no average worth quoting`() {
        val a = attempt(listOf(131_000L), durationMs = 131_000L)

        assertEquals("Fastest: round 1 at 2:11", readout(a, null).title)
    }

    @Test
    fun `a selected round gives its time and each movement's, in the athlete's own words`() {
        val a = attempt(listOf(168_000L), round(41_000L, 52_000L, 75_000L))

        val r = readout(a, 0)

        assertEquals("Round 1 · 2:48", r.title)
        assertEquals("Pull-ups 0:41 · push-ups 0:52 · squats 1:15", r.detail)
        assertNull(r.versus)
    }

    @Test
    fun `an adaptive session names its own movements`() {
        val profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        val a = attempt(listOf(168_000L), round(41_000L, 52_000L, 75_000L), profile = profile)

        assertEquals("Pull-ups 0:41 · knee push-ups 0:52 · squats 1:15", readout(a, 0).detail)
    }

    @Test
    fun `a session of unrecognised movements falls back to the plain names`() {
        assertEquals(listOf("pull-ups", "push-ups", "squats"), RoundSplits.movementNames(null))
    }

    @Test
    fun `a plain bar says it has no movement times`() {
        val r = readout(attempt(listOf(168_000L)), 0)

        assertEquals("No per-movement times for this round", r.detail)
    }

    @Test
    fun `a tapped in round says so`() {
        val sets = listOf(
            set(Exercise.PULLUP, 41_000L, manual = 1), set(Exercise.PUSHUP, 52_000L), set(Exercise.SQUAT, 75_000L)
        )

        assertTrue(readout(attempt(listOf(168_000L), sets), 0).detail.endsWith("Some reps in this round were added by hand"))
    }

    @Test
    fun `faster than your best is said with the gap and flagged faster`() {
        val a = attempt(listOf(168_000L))
        val best = attempt(listOf(177_000L))

        val v = readout(a, 0, best, Comparisons.Kind.BEST).versus!!

        assertEquals("9 s faster than your best's round 1", v.text)
        assertEquals(true, v.faster)
    }

    @Test
    fun `slower than last time is flagged slower, and a minute or more is a time`() {
        val a = attempt(listOf(168_000L))
        val last = attempt(listOf(100_000L))

        val v = readout(a, 0, last, Comparisons.Kind.LAST).versus!!

        assertEquals("1:08 slower than round 1 last time", v.text)
        assertEquals(false, v.faster)
    }

    @Test
    fun `within half a second is level`() {
        val a = attempt(listOf(168_000L))
        val best = attempt(listOf(168_300L))

        val v = readout(a, 0, best, Comparisons.Kind.BEST).versus!!

        assertEquals("Level with your best's round 1", v.text)
        assertNull(v.faster)
    }

    @Test
    fun `a comparison without that round says nothing about it`() {
        val a = attempt(listOf(168_000L, 160_000L), durationMs = 328_000L)
        val best = attempt(listOf(177_000L))

        assertNull(readout(a, 1, best, Comparisons.Kind.BEST).versus)
    }

    @Test
    fun `the round in progress is not compared and says how far it got`() {
        val a = attempt(
            listOf(160_000L), round(40_000L, 50_000L, 70_000L) + set(Exercise.PULLUP, 38_000L),
            durationMs = 240_000L, counted = 36
        )
        val best = attempt(listOf(170_000L, 150_000L))

        val r = readout(a, 1, best, Comparisons.Kind.BEST)

        assertEquals("Round 2 · 1:20 so far", r.title)
        assertEquals("6 of 30 reps · not a finished round. Pull-ups 0:38", r.detail)
        assertNull(r.versus)
    }

    @Test
    fun `an unfinished round with unknown reps does not make up a count`() {
        val a = attempt(listOf(160_000L), durationMs = 240_000L, counted = null)

        assertEquals("not a finished round", readout(a, 1).detail)
    }

    @Test
    fun `the spoken form joins title detail and versus`() {
        val a = attempt(listOf(168_000L))
        val best = attempt(listOf(177_000L))

        assertEquals(
            "Round 1 · 2:48. No per-movement times for this round. 9 s faster than your best's round 1",
            readout(a, 0, best, Comparisons.Kind.BEST).spoken()
        )
    }
}
