package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionStatsTest {

    private fun split(movement: Exercise, reps: Int, ms: Long = 10_000L, tapped: Int = 0) =
        SetSplit(movement, ms, reps, tapped)

    private fun round(
        pull: Int = 5, push: Int = 10, squat: Int = 15,
        pullMs: Long = 14_000L, pushMs: Long = 17_000L, squatMs: Long = 21_000L
    ) = listOf(
        split(Exercise.PULLUP, pull, pullMs),
        split(Exercise.PUSHUP, push, pushMs),
        split(Exercise.SQUAT, squat, squatMs)
    )

    /** An attempt whose rounds, counted reps and tapped reps are consistent with its sets. */
    private fun attempt(
        splits: List<SetSplit>,
        openReps: Int = 0,
        openTapped: Int = 0,
        profile: CindyProfile? = CindyProfile.STANDARD,
        roundSplitsMs: List<Long> = List(splits.size / 3) { 52_000L }
    ) = Attempt(
        rounds = splits.size / 3,
        reps = 0,
        atMillis = 1L,
        durationMs = 20 * 60_000L,
        roundSplitsMs = roundSplitsMs,
        profile = profile,
        manualReps = splits.sumOf { it.manualReps } + openTapped,
        countedReps = splits.sumOf { it.reps } + openReps,
        setSplits = splits
    )

    @Test
    fun `a standard session is rounds of what was banked, with the unfinished one last`() {
        val a = attempt(round() + round(), openReps = 3, roundSplitsMs = listOf(50_000L, 54_000L))
        val stats = SessionStats.from(a)!!

        assertEquals(listOf(1, 2, 3), stats.rounds.map { it.number })
        assertEquals(listOf(true, true, false), stats.rounds.map { it.finished })
        assertEquals(listOf(30, 30, 3), stats.rounds.map { it.reps })
        assertEquals(listOf(true, true, false), stats.rounds.map { it.complete })
        assertEquals(listOf<Long?>(50_000L, 54_000L, null), stats.rounds.map { it.timeMs })
        assertEquals(3, stats.unfinished?.number)
        assertEquals(
            listOf(13, 20, 30), stats.movements.map { it.reps }
        )
    }

    @Test
    fun `a full round says what it cost, a part round says what went into it`() {
        val plurals = SessionStats.plurals(CindyProfile.STANDARD)
        val a = attempt(round() + listOf(split(Exercise.PULLUP, 5)), openReps = 7)
        val stats = SessionStats.from(a)!!

        assertEquals("Round 1 · 30 of 30 · 0:52", stats.rounds[0].caption(plurals))
        assertEquals(
            "Round 2 · 12 of 30 · 5 strict pull-ups, 7 standard push-ups · unfinished",
            stats.rounds[1].caption(plurals)
        )
    }

    @Test
    fun `a skipped set is a finished round worth less than thirty`() {
        // Pull-ups skipped at zero: the cycle still moves on, and the round is finished at 25.
        val a = attempt(round(pull = 0, pullMs = 1_000L) + round())
        val stats = SessionStats.from(a)!!
        val skipped = stats.rounds[0]

        assertTrue(skipped.finished)
        assertFalse(skipped.complete)
        assertEquals(25, skipped.reps)
        assertEquals(
            "Round 1 · 25 of 30 · 10 standard push-ups, 15 air squats · 0:52",
            skipped.caption(SessionStats.plurals(CindyProfile.STANDARD))
        )
        assertEquals(55, stats.rounds.sumOf { it.reps })
        assertEquals(5, stats.movements[0].reps)
        assertEquals(1, stats.movements[0].completeSets)
        assertEquals(2, stats.movements[1].completeSets)
    }

    @Test
    fun `the movement still running at finish is a part-filled round, not a complete one`() {
        val a = attempt(listOf(split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10)), openReps = 4)
        val stats = SessionStats.from(a)!!

        assertEquals(1, stats.rounds.size)
        val only = stats.rounds.single()
        assertFalse(only.finished)
        assertEquals(listOf(5, 10, 4), only.parts.map { it.reps })
        assertEquals(listOf(true, true, false), only.parts.map { it.reachedTarget })
        // Its time is unknown, not zero: no split was ever filed for it.
        assertNull(stats.movements[2].timeMs)
        assertEquals(4, stats.movements[2].reps)
    }

    @Test
    fun `a movement not yet reached in the unfinished round shows as zero`() {
        val a = attempt(listOf(split(Exercise.PULLUP, 5)), openReps = 0)
        val stats = SessionStats.from(a)!!

        assertEquals(listOf(5, 0, 0), stats.rounds.single().parts.map { it.reps })
    }

    @Test
    fun `an attempt from before set times has no rounds or movements`() {
        val old = Attempt(rounds = 12, reps = 3, atMillis = 1L, durationMs = 20 * 60_000L)
        assertNull(SessionStats.from(old))
        // Counted, but never timed set by set: still unknown, not a guess from the round count.
        assertNull(SessionStats.from(old.copy(countedReps = 363)))
    }

    @Test
    fun `a record whose sets disagree with its round count is not trusted`() {
        val a = attempt(round() + round()).copy(rounds = 3)
        assertNull(SessionStats.from(a))
        // And one whose sets are not the cycle the engine runs.
        val reordered = attempt(listOf(split(Exercise.PUSHUP, 10)))
        assertNull(SessionStats.from(reordered))
    }

    @Test
    fun `tapped reps are read off the sets that closed, per movement`() {
        val a = attempt(
            listOf(
                split(Exercise.PULLUP, 5, tapped = 2),
                split(Exercise.PUSHUP, 10),
                split(Exercise.SQUAT, 15, tapped = 15)
            )
        )
        val stats = SessionStats.from(a)!!

        assertEquals(listOf<Int?>(2, 0, 15), stats.movements.map { it.tappedReps })
        assertEquals(17, stats.rounds.single().tappedReps)
        assertEquals(
            "Round 1 · 30 of 30 · 0:52 · 17 tapped",
            stats.rounds.single().caption(SessionStats.plurals(CindyProfile.STANDARD))
        )
    }

    @Test
    fun `the unfinished set's tapped reps are what the totals leave over`() {
        // Two tapped in the squats still running; the closed sets tapped none.
        val a = attempt(round(squat = 15).take(2), openReps = 7, openTapped = 2)
        val stats = SessionStats.from(a)!!

        assertEquals(2, stats.movements[2].tappedReps)
        assertEquals(2, stats.rounds.single().tappedReps)
    }

    @Test
    fun `tapped reps that cannot be attributed are left unsaid rather than guessed`() {
        // The record says 9 were tapped, but only 3 reps are in the set still running, and the
        // closed sets tapped none: that cannot be right, so no figure is given for that set.
        val a = attempt(round().take(2), openReps = 3, openTapped = 9)
        val stats = SessionStats.from(a)!!

        assertNull(stats.movements[2].tappedReps)
        assertNull(stats.rounds.single().tappedReps)
        assertEquals(0, stats.movements[0].tappedReps)
        assertFalse(
            stats.rounds.single().caption(SessionStats.plurals(CindyProfile.STANDARD))
                .contains("tapped")
        )
    }

    @Test
    fun `movement times, averages and shares come from finished sets`() {
        val a = attempt(round() + round(pullMs = 16_000L))
        val m = SessionStats.from(a)!!.movements

        assertEquals(30_000L, m[0].timeMs)
        assertEquals(15_000L, m[0].averageCompleteSetMs)
        assertEquals(34_000L, m[1].timeMs)
        assertEquals(42_000L, m[2].timeMs)
        assertEquals(1.0, m.sumOf { it.shareOfClock!! }, 1e-9)
        assertEquals(30_000.0 / 106_000.0, m[0].shareOfClock!!, 1e-9)
    }

    @Test
    fun `a skipped set's time counts toward the movement but not its average`() {
        val a = attempt(round() + round(pull = 2, pullMs = 4_000L))
        val m = SessionStats.from(a)!!.movements

        assertEquals(18_000L, m[0].timeMs)
        assertEquals(1, m[0].completeSets)
        assertEquals(14_000L, m[0].averageCompleteSetMs)
    }

    @Test
    fun `no share is given until every movement has a complete set`() {
        val onlyPullUps = attempt(listOf(split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 4)))
        val m = SessionStats.from(onlyPullUps)!!.movements

        assertNull(m[0].shareOfClock)
        assertNull(m[1].shareOfClock)
        // Its time and average are still real, and shown.
        assertEquals(10_000L, m[0].timeMs)
        assertNull(m[1].averageCompleteSetMs)
    }

    @Test
    fun `labels use the profile's own plurals`() {
        val adaptive = CindyProfile(
            pull = PullVariant.BAND_ASSISTED_PULL_UP, push = PushVariant.KNEE_PUSH_UP
        )
        val stats = SessionStats.from(attempt(round(), profile = adaptive))!!

        assertEquals(
            listOf("band-assisted pull-ups", "knee push-ups", "air squats"),
            stats.movements.map { it.label }
        )
        assertEquals(
            "Round 1 · 30 of 30 · 0:52",
            stats.rounds.single().caption(SessionStats.plurals(adaptive))
        )
        assertEquals(
            "Round 2 · 10 of 30 · 5 band-assisted pull-ups, 5 knee push-ups · unfinished",
            SessionStats.from(
                attempt(round() + listOf(split(Exercise.PULLUP, 5)), openReps = 5, profile = adaptive)
            )!!.rounds[1].caption(SessionStats.plurals(adaptive))
        )
    }

    @Test
    fun `a record from before profiles is the standard movements`() {
        assertEquals(
            listOf("pull-ups", "push-ups", "squats"),
            SessionStats.plurals(null).values.toList()
        )
    }

    @Test
    fun `pace is reps a minute of the workout clock`() {
        val a = attempt(round() + round())
        assertEquals(3.0, SessionStats.repsPerMinute(a)!!, 1e-9)
        assertNull(SessionStats.repsPerMinute(a.copy(durationMs = 0L)))
        assertNotNull(SessionStats.from(a))
    }
}
