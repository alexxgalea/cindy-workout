package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ComparisonsTest {

    private fun attempt(
        rounds: Int,
        reps: Int = 0,
        at: Long = 0L,
        profile: CindyProfile? = CindyProfile.STANDARD,
        roundSplitsMs: List<Long> = emptyList(),
        untrackedMs: Long = 0L
    ) = Attempt(rounds, reps, at, roundSplitsMs = roundSplitsMs, profile = profile, untrackedMs = untrackedMs)

    // ── earlier ────────────────────────────────────────────────────────────────

    @Test
    fun `earlier excludes the session itself and anything after it`() {
        val of = attempt(10, at = 2000L)
        val before = attempt(8, at = 1000L)
        val same = attempt(9, at = 2000L)
        val after = attempt(12, at = 3000L)
        assertEquals(listOf(before), Comparisons.earlier(listOf(before, same, after, of), of))
    }

    @Test
    fun `earlier excludes other categories`() {
        val of = attempt(10, at = 2000L, profile = CindyProfile.STANDARD)
        val adaptive = attempt(8, at = 1000L, profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP))
        val unrecognised = attempt(8, at = 1000L, profile = null)
        assertEquals(emptyList<Attempt>(), Comparisons.earlier(listOf(adaptive, unrecognised), of))
    }

    @Test
    fun `earlier matches two unrecognised sessions to each other`() {
        val of = attempt(10, at = 2000L, profile = null)
        val before = attempt(8, at = 1000L, profile = null)
        assertEquals(listOf(before), Comparisons.earlier(listOf(before), of))
    }

    @Test
    fun `nothing earlier than a first session`() {
        val of = attempt(10, at = 1000L)
        assertEquals(emptyList<Attempt>(), Comparisons.earlier(emptyList(), of))
    }

    // ── best and last ────────────────────────────────────────────────────────

    @Test
    fun `best is the highest score among earlier sessions`() {
        val of = attempt(20, at = 4000L)
        val weaker = attempt(10, at = 1000L)
        val strongest = attempt(15, at = 2000L)
        val middling = attempt(12, at = 3000L)
        assertEquals(strongest, Comparisons.best(listOf(weaker, strongest, middling), of))
    }

    @Test
    fun `last is the most recent earlier session, regardless of score`() {
        val of = attempt(20, at = 4000L)
        val better = attempt(15, at = 1000L)
        val mostRecent = attempt(10, at = 3000L)
        assertEquals(mostRecent, Comparisons.last(listOf(better, mostRecent), of))
    }

    @Test
    fun `best and last are null without an earlier session`() {
        val of = attempt(10, at = 1000L)
        assertNull(Comparisons.best(emptyList(), of))
        assertNull(Comparisons.last(emptyList(), of))
    }

    // ── a lower-bound attempt is still compared with, never specially excluded ──

    @Test
    fun `a lower-bound session can still be the best, and still deltas cleanly`() {
        val of = attempt(20, at = 3000L)
        val degraded = attempt(25, at = 1000L, untrackedMs = 60_000L)
        val clean = attempt(10, at = 2000L)
        assertEquals(degraded, Comparisons.best(listOf(degraded, clean), of))
        val delta = Comparisons.delta(of, degraded)
        assertEquals(of.totalReps - degraded.totalReps, delta.reps)
    }

    // ── options: dedupe and the empty case ──────────────────────────────────

    @Test
    fun `options offers both best and last when they differ`() {
        val of = attempt(20, at = 3000L)
        val best = attempt(15, at = 1000L)
        val last = attempt(5, at = 2000L)
        val options = Comparisons.options(listOf(best, last), of)
        assertEquals(listOf(Comparisons.Kind.BEST, Comparisons.Kind.LAST), options.map { it.kind })
        assertEquals("Your best", options[0].label)
        assertEquals(best, options[0].attempt)
        assertEquals("Last time", options[1].label)
        assertEquals(last, options[1].attempt)
    }

    @Test
    fun `options drops last when it is the same session as best`() {
        val of = attempt(20, at = 3000L)
        val onlyEarlierSession = attempt(15, at = 1000L)
        val options = Comparisons.options(listOf(onlyEarlierSession), of)
        assertEquals(1, options.size)
        assertEquals(Comparisons.Kind.BEST, options[0].kind)
        assertEquals("Your best · also last time", options[0].label)
    }

    @Test
    fun `options is empty with no earlier session, which is what hides the card`() {
        val of = attempt(10, at = 1000L)
        assertTrue(Comparisons.options(emptyList(), of).isEmpty())
        assertTrue(Comparisons.options(listOf(attempt(5, at = 2000L)), of).isEmpty())
    }

    // ── delta ────────────────────────────────────────────────────────────────

    @Test
    fun `delta reads reps and rounds this session minus the reference`() {
        val of = attempt(6, reps = 20, at = 2000L)
        val reference = attempt(6, at = 1000L)
        val d = Comparisons.delta(of, reference)
        assertEquals(of.totalReps - reference.totalReps, d.reps)
        assertEquals(0, d.rounds)
    }

    @Test
    fun `average round delta is positive when this session was faster`() {
        val of = attempt(2, at = 2000L, roundSplitsMs = listOf(100_000L, 100_000L))
        val reference = attempt(2, at = 1000L, roundSplitsMs = listOf(140_000L, 140_000L))
        assertEquals(40_000L, Comparisons.delta(of, reference).avgRoundMs)
        assertEquals(-40_000L, Comparisons.delta(reference, of).avgRoundMs)
    }

    @Test
    fun `average round delta is null when either side has none`() {
        val withSplits = attempt(2, at = 2000L, roundSplitsMs = listOf(100_000L, 100_000L))
        val withoutSplits = attempt(0, reps = 5, at = 1000L)
        assertNull(Comparisons.delta(withSplits, withoutSplits).avgRoundMs)
        assertNull(Comparisons.delta(withoutSplits, withSplits).avgRoundMs)
    }
}
