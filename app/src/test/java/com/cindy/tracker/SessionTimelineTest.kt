package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The session timeline's numbers, on a two-round session whose every instant is easy to read:
 *
 * ```
 * round 1  0:00 pull-ups 5 (10 s) · push-ups 10 (20 s) · squats 15 (30 s)   ends 1:00
 * round 2  1:00 pull-ups 5 (8 s)  · push-ups 10 (17 s) · squats 15 (25 s)   ends 1:50
 * then     pull-ups, 3 reps in, when the clock stops at 2:00 (63 reps)
 * ```
 */
class SessionTimelineTest {

    private val sets = listOf(
        SetSplit(Exercise.PULLUP, 10_000L, 5, 0),
        SetSplit(Exercise.PUSHUP, 20_000L, 10, 0),
        SetSplit(Exercise.SQUAT, 30_000L, 15, 0),
        SetSplit(Exercise.PULLUP, 8_000L, 5, 0),
        SetSplit(Exercise.PUSHUP, 17_000L, 10, 0),
        SetSplit(Exercise.SQUAT, 25_000L, 15, 0)
    )

    private fun attempt(
        at: Long = 1_000L,
        splits: List<SetSplit> = sets,
        roundSplits: List<Long> = listOf(60_000L, 50_000L),
        counted: Int? = 63,
        durationMs: Long = 120_000L,
        manual: Int = 0,
        untracked: Long = 0L
    ) = Attempt(
        rounds = roundSplits.size, reps = 3, atMillis = at, durationMs = durationMs,
        roundSplitsMs = roundSplits, countedReps = counted, setSplits = splits,
        manualReps = manual, untrackedMs = untracked
    )

    /** One mark a second inside every set, ending on the set's own end, as the engine files them. */
    private fun marks(a: Attempt, manualFrom: Int = Int.MAX_VALUE): List<RepMark> {
        val out = mutableListOf<RepMark>()
        var start = 0L
        for (s in a.setSplits) {
            for (k in 1..s.reps) {
                out += RepMark(
                    start + s.ms * k / s.reps, s.movement, manual = out.size >= manualFrom
                )
            }
            start += s.ms
        }
        val running = (a.countedReps ?: 0) - out.size
        for (k in 1..running) {
            out += RepMark(start + k * 1_000L, Exercise.PULLUP, manual = out.size >= manualFrom)
        }
        return out
    }

    private fun trace(vararg samples: Pair<Long, Int>) = HeartRateTrace(
        startedAtMillis = 0L, samples = samples.map { HeartRateSample(it.first, it.second) },
        pauses = emptyList()
    )

    // ── reps: exact versus per set ──────────────────────────────────────────

    @Test
    fun `with valid marks the reps are one step per rep`() {
        val a = attempt()
        val t = SessionTimeline.of(a, marks(a), null)

        val series = t.reps!!
        assertTrue(series.exact)
        assertEquals(64, series.points.size)
        assertEquals(RepPoint(0L, 0, 0), series.points.first())
        assertEquals(63, series.points.last().reps)
    }

    @Test
    fun `an exact count is the marks at or before the instant`() {
        val a = attempt()
        val t = SessionTimeline.of(a, marks(a), null)

        // The first pull-up banks at 2 s, the fifth at 10 s.
        assertEquals(0, t.at(1_999L).reps)
        assertEquals(1, t.at(2_000L).reps)
        assertEquals(5, t.at(10_000L).reps)
        assertEquals(5, t.at(10_001L).reps)
        assertEquals(63, t.at(120_000L).reps)
    }

    @Test
    fun `without marks the reps are per set and snap to the last finished set`() {
        val a = attempt()
        val t = SessionTimeline.of(a, marks = null, trace = null)

        val series = t.reps!!
        assertFalse(series.exact)
        // The origin, six finished sets, and the clock stopping on the total counted by then.
        assertEquals(
            listOf(0L, 10_000L, 30_000L, 60_000L, 68_000L, 85_000L, 110_000L, 120_000L),
            series.points.map { it.clockMs }
        )
        assertEquals(listOf(0, 5, 15, 30, 35, 45, 60, 63), series.points.map { it.reps })
        assertEquals(0, t.at(9_999L).reps)
        assertEquals(5, t.at(25_000L).reps)
        assertEquals(30, t.at(67_999L).reps)
        assertEquals(63, t.at(120_000L).reps)
    }

    @Test
    fun `marks that do not add up to what was counted fall back to the sets`() {
        val a = attempt()
        val short = marks(a).dropLast(1)

        val t = SessionTimeline.of(a, short, null)

        assertFalse(t.reps!!.exact)
    }

    @Test
    fun `marks running past the clock fall back to the sets`() {
        val a = attempt()
        val late = marks(a).dropLast(1) + RepMark(125_000L, Exercise.PULLUP, false)

        assertFalse(SessionTimeline.of(a, late, null).reps!!.exact)
    }

    @Test
    fun `a record from before rep times and set times has no reps line at all`() {
        val old = attempt(splits = emptyList(), counted = null)
        val t = SessionTimeline.of(old, null, null)

        assertNull(t.reps)
        assertNull(t.at(60_000L).reps)
        assertFalse(t.hasData)
    }

    @Test
    fun `a set record that disagrees with the total is not plotted`() {
        val a = attempt(counted = 40)

        assertNull(SessionTimeline.of(a, null, null).reps)
    }

    @Test
    fun `a session with nothing banked has no reps line`() {
        val a = attempt(splits = emptyList(), counted = 0, roundSplits = emptyList())

        assertNull(SessionTimeline.of(a, emptyList(), null).reps)
    }

    @Test
    fun `reps tapped in are counted apart from the rest`() {
        val a = attempt(manual = 4)
        val t = SessionTimeline.of(a, marks(a, manualFrom = 59), null)

        val end = t.at(120_000L)
        assertEquals(63, end.reps)
        assertEquals(4, end.manualReps)
        assertEquals(0, t.at(60_000L).manualReps)
        assertTrue(t.readout(end).detail!!.startsWith("63 reps, 4 by hand"))
    }

    @Test
    fun `a score the camera could not stand behind says at least`() {
        val a = attempt(untracked = 60_000L)
        val t = SessionTimeline.of(a, marks(a), null)

        assertTrue(a.scoreIsLowerBound)
        assertTrue(t.readout(t.at(120_000L)).detail!!.startsWith("at least 63 reps"))
        assertTrue(t.describeRound(t.rounds[1]).contains("at least 60 reps by its end"))
    }

    // ── rounds and sets ─────────────────────────────────────────────────────

    @Test
    fun `round ends are the running total of the splits, and the unfinished round has a span`() {
        val t = SessionTimeline.of(attempt(), null, null)

        assertEquals(listOf(60_000L, 110_000L), t.roundEnds)
        assertEquals(
            listOf(
                RoundSpan(1, 0L, 60_000L, true),
                RoundSpan(2, 60_000L, 110_000L, true),
                RoundSpan(3, 110_000L, 120_000L, false)
            ),
            t.rounds
        )
    }

    @Test
    fun `sets carry their round, and the one still running follows the last finished`() {
        val t = SessionTimeline.of(attempt(), null, null)

        assertEquals(7, t.sets.size)
        assertEquals(SetSpan(0L, 10_000L, Exercise.PULLUP, 1, false), t.sets.first())
        assertEquals(SetSpan(110_000L, 120_000L, Exercise.PULLUP, 3, true), t.sets.last())
    }

    @Test
    fun `the round in progress, and its movement, follow the cursor`() {
        val t = SessionTimeline.of(attempt(), null, null)

        assertEquals(1, t.at(0L).round)
        assertEquals(Exercise.PULLUP, t.at(0L).movement)
        assertEquals(Exercise.PUSHUP, t.at(20_000L).movement)
        assertEquals(1, t.at(59_000L).round)
        // The instant a round ends it is still that round, and its last set.
        assertEquals(1, t.at(60_000L).round)
        assertEquals(Exercise.SQUAT, t.at(60_000L).movement)
        assertEquals(2, t.at(60_001L).round)
        assertEquals(Exercise.PULLUP, t.at(60_001L).movement)
        // After the last finished round the clock was running on a third.
        assertEquals(3, t.at(115_000L).round)
        assertEquals(3, t.at(120_000L).round)
    }

    @Test
    fun `a session that ends exactly on a round does not invent another`() {
        val a = attempt(splits = sets, roundSplits = listOf(60_000L, 50_000L), durationMs = 110_000L)
        val t = SessionTimeline.of(a, null, null)

        assertEquals(2, t.rounds.size)
        assertEquals(2, t.at(110_000L).round)
    }

    @Test
    fun `an instant outside the clock is held to it`() {
        val t = SessionTimeline.of(attempt(), null, null)

        assertEquals(0L, t.at(-5L).clockMs)
        assertEquals(120_000L, t.at(999_999L).clockMs)
    }

    // ── heart rate ──────────────────────────────────────────────────────────

    @Test
    fun `heart rate is cut into runs wherever the watch fell silent for longer than a hold`() {
        val a = attempt()
        val t = SessionTimeline.of(
            a, null,
            trace(
                0L to 90, 1_000L to 95, 6_000L to 100,        // exactly one hold apart: still joined
                20_000L to 120, 21_000L to 122                // a long silence before this
            )
        )

        assertEquals(2, t.heartRuns.size)
        assertEquals(3, t.heartRuns[0].size)
        assertEquals(listOf(120, 122), t.heartRuns[1].map { it.bpm })
    }

    @Test
    fun `samples outside the clock, or not a plausible heart rate, are not drawn`() {
        val a = attempt()
        val t = SessionTimeline.of(
            a, null,
            trace(-1_000L to 90, 1_000L to 20, 2_000L to 130, 120_000L to 140, 130_000L to 150)
        )

        assertEquals(listOf(listOf(130)), t.heartRuns.map { run -> run.map { it.bpm } })
    }

    @Test
    fun `the bpm is the latest reading, held no longer than the hold`() {
        val t = SessionTimeline.of(attempt(), null, trace(10_000L to 130, 12_000L to 140))

        assertNull(t.at(9_999L).bpm)
        assertEquals(130, t.at(10_000L).bpm)
        assertEquals(130, t.at(11_999L).bpm)
        assertEquals(140, t.at(12_000L).bpm)
        assertEquals(140, t.at(17_000L).bpm)
        assertNull(t.at(17_001L).bpm)
    }

    @Test
    fun `with no trace there is no bpm and no heart runs`() {
        val t = SessionTimeline.of(attempt(), null, null)

        assertTrue(t.heartRuns.isEmpty())
        assertNull(t.at(30_000L).bpm)
    }

    @Test
    fun `a trace alone is enough to have something to draw`() {
        val old = attempt(splits = emptyList(), counted = null)
        val t = SessionTimeline.of(old, null, trace(1_000L to 100))

        assertTrue(t.hasData)
        assertNull(t.reps)
    }

    @Test
    fun `a round's average bpm is the mean of the samples inside it`() {
        val t = SessionTimeline.of(attempt(), null, trace(10_000L to 100, 20_000L to 120, 70_000L to 160))

        assertEquals(110, t.averageBpm(0L, 60_000L))
        assertEquals(160, t.averageBpm(60_000L, 110_000L))
        assertNull(t.averageBpm(110_000L, 120_000L))
    }

    // ── against the reference ───────────────────────────────────────────────

    /** Slower in round one (70 s), level after: 1:10 then 2:00, against 1:00 and 1:50. */
    private fun slower(at: Long = 500L) = attempt(
        at = at, splits = emptyList(), roundSplits = listOf(70_000L, 50_000L), counted = null
    )

    @Test
    fun `ahead is the reference's round end minus ours, positive when we were faster`() {
        val t = SessionTimeline.of(
            attempt(), null, null, slower(), Comparisons.Kind.BEST, referenceMarks = null
        )

        // Both have finished round one by 1:10; we were ten seconds quicker.
        assertEquals(10_000L, t.at(70_000L).aheadMs)
        assertEquals(1, t.at(70_000L).aheadRound)
        // Round two ended at 1:50 for us and 2:00 for them.
        assertEquals(10_000L, t.at(120_000L).aheadMs)
        assertEquals(2, t.at(120_000L).aheadRound)
    }

    @Test
    fun `ahead is only said once both sessions have finished the round`() {
        val t = SessionTimeline.of(attempt(), null, null, slower(), Comparisons.Kind.BEST, null)

        // We finished round one at 1:00; they had not. Nothing to compare yet, and no guess at it.
        assertNull(t.at(60_000L).aheadMs)
        assertNull(t.at(69_999L).aheadMs)
        assertNull(t.at(10_000L).aheadMs)
    }

    @Test
    fun `behind is negative`() {
        val faster = attempt(at = 500L, roundSplits = listOf(50_000L, 50_000L))
        val t = SessionTimeline.of(
            attempt(), null, null, faster, Comparisons.Kind.LAST, null
        )

        assertEquals(-10_000L, t.at(60_000L).aheadMs)
        assertEquals(-10_000L, t.at(110_000L).aheadMs)
    }

    @Test
    fun `a reference with fewer rounds is compared on the last round they share`() {
        val shorter = attempt(
            at = 500L, roundSplits = listOf(65_000L), splits = emptyList(), counted = null,
            durationMs = 100_000L
        )
        val t = SessionTimeline.of(attempt(), null, null, shorter, Comparisons.Kind.BEST, null)

        assertEquals(5_000L, t.at(65_000L).aheadMs)
        // Their second round never happened, so ours is not measured against it.
        assertEquals(1, t.at(115_000L).aheadRound)
        assertEquals(5_000L, t.at(115_000L).aheadMs)
        assertNull(t.aheadOfReference(2))
    }

    @Test
    fun `no reference means no comparison anywhere`() {
        val a = attempt()
        val t = SessionTimeline.of(a, marks(a), null)

        assertNull(t.at(100_000L).aheadMs)
        assertNull(t.reference)
        assertNull(t.legend())
    }

    @Test
    fun `the reference's marks are checked against the reference, not this session`() {
        val a = attempt()
        val ref = attempt(at = 500L, counted = 60, splits = emptyList(), roundSplits = listOf(70_000L))
        // Valid for the reviewed session (63 marks), wrong for the reference (counted 60).
        val t = SessionTimeline.of(a, marks(a), null, ref, Comparisons.Kind.BEST, marks(a))

        assertTrue(t.reps!!.exact)
        assertNull(t.reference!!.reps)
    }

    @Test
    fun `each side is exact or per set on its own`() {
        val a = attempt()
        val ref = attempt(at = 500L)
        val t = SessionTimeline.of(a, marks(a), null, ref, Comparisons.Kind.BEST, referenceMarks = null)

        assertTrue(t.reps!!.exact)
        assertFalse(t.reference!!.reps!!.exact)
        assertEquals("Dashed: your best. Reps are plotted per set for your best.", t.legend())
    }

    // ── the words ───────────────────────────────────────────────────────────

    @Test
    fun `the idle readout is the whole session in a line`() {
        assertEquals("2:00 · 2 rounds + 3", SessionTimeline.of(attempt(), null, null).idleReadout().title)
        val flat = attempt().copy(rounds = 1, reps = 0)
        assertEquals("2:00 · 1 round", SessionTimeline.of(flat, null, null).idleReadout().title)
    }

    @Test
    fun `a scrubbed instant reads as a title and a detail`() {
        val a = attempt()
        val t = SessionTimeline.of(
            a, marks(a), trace(0L to 150, 70_000L to 158), slower(), Comparisons.Kind.BEST, null
        )

        val r = t.readout(t.at(72_000L))

        assertEquals("1:12 · Round 2 · Push-ups", r.title)
        assertEquals("37 reps · 158 bpm · round 1: 10 s ahead of your best", r.detail)
    }

    @Test
    fun `behind and level are said as such, and a last session is named as last time`() {
        val a = attempt()
        val faster = attempt(at = 500L, roundSplits = listOf(50_000L, 50_000L))
        val level = attempt(at = 400L)

        val behind = SessionTimeline.of(a, null, null, faster, Comparisons.Kind.LAST, null)
        assertTrue(behind.readout(behind.at(60_000L)).detail!!.endsWith("round 1: 10 s behind last time"))
        val same = SessionTimeline.of(a, null, null, level, Comparisons.Kind.BEST, null)
        assertTrue(same.readout(same.at(60_000L)).detail!!.endsWith("round 1: level with your best"))
    }

    @Test
    fun `a record with nothing but a clock still reads as a title`() {
        val old = attempt(splits = emptyList(), counted = null)
        val t = SessionTimeline.of(old, null, null)

        val r = t.readout(t.at(30_000L))
        assertEquals("0:30 · Round 1", r.title)
        assertNull(r.detail)
    }

    @Test
    fun `a movement is named in the session's own plural`() {
        val adaptive = attempt().copy(profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP))
        val t = SessionTimeline.of(adaptive, null, null)

        assertEquals("0:15 · Round 1 · Knee push-ups", t.readout(t.at(15_000L)).title)
    }

    @Test
    fun `talkback hears a round the way the spec describes it`() {
        val a = attempt()
        val t = SessionTimeline.of(
            a, marks(a), trace(62_000L to 150, 100_000L to 166), slower(), Comparisons.Kind.BEST, null
        )

        assertEquals(
            "Round 2, 1:00 to 1:50, 50 seconds, 60 reps by its end, 158 beats per minute on average, " +
                "10 seconds ahead of your best",
            t.describeRound(t.rounds[1])
        )
    }

    @Test
    fun `talkback says the unfinished round is unfinished, and compares nothing`() {
        val a = attempt()
        val t = SessionTimeline.of(a, marks(a), null, slower(), Comparisons.Kind.BEST, null)

        val said = t.describeRound(t.rounds[2])
        assertEquals("Round 3, in progress, 1:50 to the end at 2:00, 63 reps by the end", said)
    }

    @Test
    fun `a minute and a second are spoken as such`() {
        assertEquals("1 minute 1 second", SessionTimeline.spokenSeconds(61))
        assertEquals("2 minutes", SessionTimeline.spokenSeconds(120))
        assertEquals("38 seconds", SessionTimeline.spokenSeconds(38))
        assertEquals("1 min 5 s", SessionTimeline.shortSeconds(65))
    }

    @Test
    fun `the legend names the dashed line and says when reps are per set`() {
        val a = attempt()
        val ref = attempt(at = 500L)
        val exact = SessionTimeline.of(a, marks(a), null, ref, Comparisons.Kind.LAST, marks(ref))
        assertEquals("Dashed: last time.", exact.legend())

        val perSet = SessionTimeline.of(a, null, null, ref, Comparisons.Kind.BEST, null)
        assertEquals(
            "Dashed: your best. Reps are plotted per set for both sessions.", perSet.legend()
        )
        assertNotNull(perSet.reps)
    }
}
