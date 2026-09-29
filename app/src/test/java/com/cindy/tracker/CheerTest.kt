package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

class CheerTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val today = LocalDate.of(2026, 9, 9)
    private val monday = DayOfWeek.MONDAY

    /** 13 rounds + 10 reps is 400 reps; the score is set with rounds and reps, not a total. */
    private fun attempt(
        iso: String, rounds: Int = 13, reps: Int = 10, hour: Int = 12
    ): Attempt {
        val at = LocalDate.parse(iso).atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
        return Attempt(rounds = rounds, reps = reps, atMillis = at, durationMs = 20 * 60_000L)
    }

    private fun headline(vararg a: Attempt) = Cheer.headline(a.toList(), today, zone, monday)

    private fun nextStep(vararg a: Attempt) = Cheer.nextStep(a.toList(), today, zone, monday)

    private fun forResult(all: List<Attempt>, one: Attempt) =
        Cheer.forResult(all, one, zone, monday)

    @Test
    fun `no attempts opens with the first Cindy`() {
        assertEquals("Your first Cindy starts everything.", headline())
    }

    @Test
    fun `a record set today is announced with its score`() {
        assertEquals(
            "New personal record: 15.",
            headline(attempt("2026-08-01"), attempt("2026-09-09", rounds = 15, reps = 0))
        )
    }

    @Test
    fun `three days in a row is a milestone`() {
        assertEquals(
            "3 days in a row.",
            headline(
                attempt("2026-09-07", 15, 0), attempt("2026-09-08", 14, 0),
                attempt("2026-09-09", 13, 0)
            )
        )
    }

    @Test
    fun `the longest streak yet is named`() {
        assertEquals(
            "Longest streak yet: 2 days.",
            headline(
                attempt("2026-08-01", 15, 0), attempt("2026-09-08", 14, 0),
                attempt("2026-09-09", 13, 0)
            )
        )
    }

    @Test
    fun `tying the longest streak is not called the longest yet`() {
        val earlier = listOf("2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04")
            .map { attempt(it, 15, 0) }
        val current = listOf("2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09")
            .map { attempt(it, 13, 0) }
        assertTrue(headline(*(earlier + current).toTypedArray()) != "Longest streak yet: 4 days.")
    }

    @Test
    fun `beating the longest streak by a day is named`() {
        val earlier = listOf("2026-08-01", "2026-08-02", "2026-08-03")
            .map { attempt(it, 15, 0) }
        val current = listOf("2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09")
            .map { attempt(it, 13, 0) }
        assertEquals(
            "Longest streak yet: 4 days.",
            headline(*(earlier + current).toTypedArray())
        )
    }

    @Test
    fun `a streak that yesterday kept alive invites training today`() {
        assertEquals(
            "Train today to make it 3 days.",
            headline(attempt("2026-09-07"), attempt("2026-09-08"))
        )
    }

    @Test
    fun `three trained weeks in a row are counted`() {
        assertEquals(
            "3 weeks in a row.",
            headline(
                attempt("2026-08-26", 15, 0), attempt("2026-09-02", 14, 0),
                attempt("2026-09-09", 13, 0)
            )
        )
    }

    @Test
    fun `a week without a session yet says what one would make`() {
        assertEquals(
            "A session this week makes it 3 weeks in a row.",
            headline(attempt("2026-08-26"), attempt("2026-09-02"))
        )
    }

    @Test
    fun `more sessions than last week is said with the difference`() {
        assertEquals(
            "2 sessions this week, 2 more than last week.",
            headline(
                attempt("2026-08-10", 16, 0), attempt("2026-09-07", 14, 0),
                attempt("2026-09-09", 13, 0)
            )
        )
    }

    @Test
    fun `best above the first attempt is said in reps`() {
        assertEquals(
            "Your best is 100 reps above your first Cindy.",
            headline(attempt("2026-08-01"), attempt("2026-08-10", 16, 20))
        )
    }

    @Test
    fun `otherwise the headline states the best`() {
        assertEquals("Your best is 13 + 10.", headline(attempt("2026-08-01")))
    }

    @Test
    fun `an adaptive category is named for what it is`() {
        val knee = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        val first = attempt("2026-08-01").copy(profile = knee)
        val best = attempt("2026-08-10", 16, 20).copy(profile = knee)
        assertEquals(
            "Your best is 100 reps above your first Adaptive Cindy.",
            headline(first, best)
        )
    }

    @Test
    fun `next step counts the days to the next daily milestone`() {
        assertEquals(
            "1 more day to a 3-day streak.",
            nextStep(attempt("2026-09-08"), attempt("2026-09-09"))
        )
    }

    @Test
    fun `next step falls back to weeks when no day streak runs`() {
        assertEquals(
            "2 more weeks to a 4-week streak.",
            nextStep(attempt("2026-08-26"), attempt("2026-09-02"))
        )
    }

    @Test
    fun `next step is null with nothing to count`() {
        assertNull(nextStep())
    }

    @Test
    fun `the very first attempt is celebrated as the first`() {
        val a = attempt("2026-09-09")
        assertEquals(
            listOf(Celebration(Celebration.Kind.FIRST, "First Cindy on the board.")),
            forResult(listOf(a), a)
        )
    }

    @Test
    fun `a record that completes a streak milestone gives both`() {
        val last = attempt("2026-09-09", 15, 0)
        val all = listOf(attempt("2026-09-07"), attempt("2026-09-08"), last)
        assertEquals(
            listOf(
                Celebration(Celebration.Kind.RECORD, "New personal record."),
                Celebration(Celebration.Kind.DAILY, "3 days in a row.")
            ),
            forResult(all, last)
        )
    }

    @Test
    fun `a second session on the same day adds no streak line`() {
        val last = attempt("2026-09-09", 12, 0, hour = 18)
        val all = listOf(
            attempt("2026-09-07", 15, 0), attempt("2026-09-08", 14, 0),
            attempt("2026-09-09", 13, 0, hour = 8), last
        )
        assertTrue(forResult(all, last).isEmpty())
    }

    @Test
    fun `a new longest streak is celebrated`() {
        val last = attempt("2026-09-09", 12, 0)
        val all = listOf(attempt("2026-08-01", 15, 0), attempt("2026-09-08", 14, 0), last)
        assertEquals(
            listOf(Celebration(Celebration.Kind.DAILY, "Longest streak yet: 2 days.")),
            forResult(all, last)
        )
    }

    @Test
    fun `a weekly milestone is celebrated`() {
        val last = attempt("2026-09-09", 12, 0)
        val all = listOf(
            attempt("2026-08-19", 15, 0), attempt("2026-08-26", 14, 0),
            attempt("2026-09-02", 13, 0), last
        )
        assertEquals(
            listOf(Celebration(Celebration.Kind.WEEKLY, "4 weeks in a row.")),
            forResult(all, last)
        )
    }

    @Test
    fun `an attempt that is not stored celebrates nothing`() {
        val stored = attempt("2026-09-08")
        assertTrue(forResult(listOf(stored), attempt("2026-09-09")).isEmpty())
    }
}
