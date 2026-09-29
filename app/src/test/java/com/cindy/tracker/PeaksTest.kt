package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

class PeaksTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val today = LocalDate.of(2026, 9, 9)
    private val monday = DayOfWeek.MONDAY
    private val knee = CindyProfile(push = PushVariant.KNEE_PUSH_UP)

    private fun attempt(
        iso: String,
        rounds: Int,
        reps: Int = 0,
        profile: CindyProfile? = CindyProfile.STANDARD,
        durationMs: Long = 20 * 60_000L,
        splits: List<Long> = List(rounds) { 60_000L },
        untrackedMs: Long = 0L
    ): Attempt {
        val at = LocalDate.parse(iso).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        return Attempt(
            rounds = rounds, reps = reps, atMillis = at, durationMs = durationMs,
            roundSplitsMs = splits, profile = profile, untrackedMs = untrackedMs
        )
    }

    private fun peaks(
        attempts: List<Attempt>, category: CindyProfile? = CindyProfile.STANDARD
    ) = Peaks.of(attempts, category, today, zone, monday)

    private fun List<Peak>.titled(title: String) = firstOrNull { it.title == title }

    @Test
    fun `no attempts gives no peaks`() {
        assertTrue(peaks(emptyList()).isEmpty())
    }

    @Test
    fun `top three scores come in order and a tie goes to the more recent`() {
        val list = peaks(
            listOf(
                attempt("2026-08-01", 10), attempt("2026-08-03", 12),
                attempt("2026-08-05", 12), attempt("2026-08-07", 8)
            )
        )
        val top = list.take(3)
        assertEquals(listOf("Best score", "2nd best", "3rd best"), top.map { it.title })
        assertEquals(listOf(1, 2, 3), top.map { it.rank })
        assertEquals(listOf("12", "12", "10"), top.map { it.value })
        assertEquals("5 Aug 2026 · 360 reps", top[0].detail)
        assertEquals("3 Aug 2026 · 360 reps", top[1].detail)
    }

    @Test
    fun `a score with extra reps is labelled with them`() {
        val list = peaks(listOf(attempt("2026-08-01", 10, reps = 5)))
        assertEquals("10 + 5", list[0].value)
        assertEquals("1 Aug 2026 · 305 reps", list[0].detail)
    }

    @Test
    fun `lower bound attempts are left out of scores and rounds`() {
        val list = peaks(
            listOf(
                attempt("2026-08-01", 10),
                attempt("2026-08-02", 20, untrackedMs = 60_000L, splits = listOf(1_000L))
            )
        )
        assertEquals("10", list.titled("Best score")!!.value)
        assertNull(list.titled("2nd best"))
        assertEquals("1:00", list.titled("Fastest round")!!.value)
    }

    @Test
    fun `another category is left out of scores but counted in streaks and weeks`() {
        val all = listOf(
            attempt("2026-08-03", 10),
            attempt("2026-08-04", 30, profile = knee),
            attempt("2026-08-05", 30, profile = knee)
        )
        val list = peaks(all)
        assertEquals("10", list.titled("Best score")!!.value)
        assertNull(list.titled("2nd best"))
        assertEquals("3 days", list.titled("Longest daily streak")!!.value)
        assertEquals("3 sessions", list.titled("Biggest week")!!.value)
        assertNull(list.titled("Most reps in a week"))
    }

    @Test
    fun `fastest round names the round`() {
        val list = peaks(
            listOf(attempt("2026-08-01", 3, splits = listOf(70_000L, 55_000L, 62_000L)))
        )
        val fastest = list.titled("Fastest round")!!
        assertEquals("0:55", fastest.value)
        assertEquals("1 Aug 2026 · round 2", fastest.detail)
        assertEquals(1, fastest.rank)
    }

    @Test
    fun `fastest round tie goes to the more recent attempt`() {
        val list = peaks(
            listOf(
                attempt("2026-08-01", 1, splits = listOf(50_000L)),
                attempt("2026-08-09", 1, splits = listOf(50_000L))
            )
        )
        assertEquals("9 Aug 2026 · round 1", list.titled("Fastest round")!!.detail)
    }

    @Test
    fun `best average round ignores a session stopped early`() {
        val list = peaks(
            listOf(
                attempt("2026-08-01", 10, splits = List(10) { 100_000L }),
                attempt(
                    "2026-08-02", 3, durationMs = 5 * 60_000L,
                    splits = List(3) { 30_000L }
                )
            )
        )
        val best = list.titled("Best average round")!!
        assertEquals("1:40", best.value)
        assertEquals("1 Aug 2026 · 10 rounds", best.detail)
        assertEquals("0:30", list.titled("Fastest round")!!.value)
    }

    @Test
    fun `best average round tie goes to the more recent session`() {
        val list = peaks(
            listOf(attempt("2026-08-01", 10), attempt("2026-08-09", 10))
        )
        assertEquals("9 Aug 2026 · 10 rounds", list.titled("Best average round")!!.detail)
    }

    @Test
    fun `a one day streak gives no streak peak`() {
        val list = peaks(listOf(attempt("2026-09-09", 10), attempt("2026-08-01", 10)))
        assertNull(list.titled("Longest daily streak"))
        assertNull(list.titled("Longest weekly streak"))
    }

    @Test
    fun `a daily streak ending today or yesterday is running now`() {
        val ends = listOf("2026-09-09", "2026-09-08")
        for (last in ends) {
            val end = LocalDate.parse(last)
            val list = peaks(
                listOf(attempt(end.minusDays(1).toString(), 10), attempt(last, 10))
            )
            val streak = list.titled("Longest daily streak")!!
            assertEquals("2 days", streak.value)
            assertEquals("Running now", streak.detail)
        }
    }

    @Test
    fun `an old daily streak says when it ended`() {
        val list = peaks(
            listOf(attempt("2026-08-03", 10), attempt("2026-08-04", 10))
        )
        assertEquals("Ended 4 Aug 2026", list.titled("Longest daily streak")!!.detail)
    }

    @Test
    fun `weekly streak is running now through last week and ended after that`() {
        val recent = peaks(
            listOf(attempt("2026-08-26", 10), attempt("2026-09-02", 10))
        )
        val streak = recent.titled("Longest weekly streak")!!
        assertEquals("2 weeks", streak.value)
        assertEquals("Running now", streak.detail)

        val old = peaks(listOf(attempt("2026-08-05", 10), attempt("2026-08-12", 10)))
        assertEquals(
            "Ended week of 10 Aug 2026", old.titled("Longest weekly streak")!!.detail
        )
    }

    @Test
    fun `biggest week tie goes to the more recent week`() {
        val list = peaks(
            listOf(
                attempt("2026-08-03", 10), attempt("2026-08-04", 10),
                attempt("2026-08-17", 10), attempt("2026-08-18", 10)
            )
        )
        val week = list.titled("Biggest week")!!
        assertEquals("2 sessions", week.value)
        assertEquals("Week of 17 Aug 2026", week.detail)
    }

    @Test
    fun `most reps in a week is absent when only one week was trained`() {
        val list = peaks(listOf(attempt("2026-08-03", 10), attempt("2026-08-04", 10)))
        assertNull(list.titled("Most reps in a week"))
        assertTrue(list.titled("Biggest week") != null)
    }

    @Test
    fun `most reps in a week sums the week and ties go to the more recent`() {
        val list = peaks(
            listOf(
                attempt("2026-08-03", 10), attempt("2026-08-04", 10),
                attempt("2026-08-17", 20), attempt("2026-09-01", 5)
            )
        )
        val reps = list.titled("Most reps in a week")!!
        assertEquals("600 reps", reps.value)
        assertEquals("Week of 17 Aug 2026", reps.detail)
        assertFalse(list.any { it.rank !in 1..3 })
    }

    private fun withSets(base: Attempt, vararg sets: SetSplit) =
        base.copy(setSplits = sets.toList())

    private fun pull(ms: Long, reps: Int = 5, manual: Int = 0) =
        SetSplit(Exercise.PULLUP, ms, reps, manual)

    @Test
    fun `the fastest measured set of each movement peaks with the right plural`() {
        val a = withSets(
            attempt("2026-08-03", 10),
            pull(15_000), SetSplit(Exercise.PUSHUP, 17_000, 10, 0),
            SetSplit(Exercise.SQUAT, 21_000, 15, 0), pull(13_500)
        )
        val list = peaks(listOf(a))
        val fastPull = list.titled("Fastest 5 strict pull-ups")!!
        assertEquals("0:13", fastPull.value)
        assertEquals("3 Aug 2026", fastPull.detail)
        assertEquals(1, fastPull.rank)
        assertEquals("0:17", list.titled("Fastest 10 standard push-ups")!!.value)
        assertEquals("0:21", list.titled("Fastest 15 air squats")!!.value)
        assertEquals(
            "Best average round",
            list.take(list.indexOfFirst { it.title.startsWith("Fastest 5") }).last().title
        )
    }

    @Test
    fun `the title uses the plural of the category`() {
        val a = withSets(
            attempt("2026-08-03", 10, profile = knee), SetSplit(Exercise.PUSHUP, 9_000, 10, 0)
        )
        assertTrue(peaks(listOf(a), knee).any { it.title == "Fastest 10 ${knee.push.plural}" })
    }

    @Test
    fun `manual and skipped sets never peak`() {
        val a = withSets(
            attempt("2026-08-03", 10),
            pull(9_000, manual = 1), pull(8_000, reps = 3), pull(20_000)
        )
        assertEquals("0:20", peaks(listOf(a)).titled("Fastest 5 strict pull-ups")!!.value)
        val none = withSets(attempt("2026-08-03", 10), pull(9_000, manual = 5))
        assertNull(peaks(listOf(none)).titled("Fastest 5 strict pull-ups"))
    }

    @Test
    fun `a lower-bound attempt never peaks a set`() {
        val lost = withSets(attempt("2026-08-03", 10, untrackedMs = 30_000L), pull(9_000))
        val ok = withSets(attempt("2026-08-04", 10), pull(15_000))
        assertEquals("0:15", peaks(listOf(lost, ok)).titled("Fastest 5 strict pull-ups")!!.value)
        assertNull(peaks(listOf(lost)).titled("Fastest 5 strict pull-ups"))
    }

    @Test
    fun `no category gives no set peaks`() {
        val a = withSets(attempt("2026-08-03", 10, profile = null), pull(9_000))
        assertFalse(
            peaks(listOf(a), null).any {
                it.title.startsWith("Fastest ") && it.title != "Fastest round"
            }
        )
    }

    @Test
    fun `a tied set goes to the more recent attempt`() {
        val older = withSets(attempt("2026-08-03", 10), pull(14_000))
        val newer = withSets(attempt("2026-08-10", 10), pull(14_000))
        val set = peaks(listOf(older, newer)).titled("Fastest 5 strict pull-ups")!!
        assertEquals("10 Aug 2026", set.detail)
        val reversed = peaks(listOf(newer, older)).titled("Fastest 5 strict pull-ups")!!
        assertEquals("10 Aug 2026", reversed.detail)
    }
}
