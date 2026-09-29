package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

class ProgressTest {

    private val zone = ZoneId.of("Europe/Bucharest")
    private val today = LocalDate.of(2026, 9, 9)
    private val monday = DayOfWeek.MONDAY
    private val knee = CindyProfile(push = PushVariant.KNEE_PUSH_UP)

    private fun attempt(
        iso: String,
        rounds: Int,
        reps: Int = 0,
        hour: Int = 12,
        profile: CindyProfile? = CindyProfile.STANDARD,
        durationMs: Long = 20 * 60_000L,
        splits: List<Long> = List(rounds) { 60_000L },
        untrackedMs: Long = 0L
    ): Attempt {
        val at = LocalDate.parse(iso).atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
        return Attempt(
            rounds = rounds, reps = reps, atMillis = at, durationMs = durationMs,
            roundSplitsMs = splits, profile = profile, untrackedMs = untrackedMs
        )
    }

    /** An attempt worth exactly [total] reps (rounds of 30 plus the remainder). */
    private fun scored(
        iso: String, total: Int, profile: CindyProfile? = CindyProfile.STANDARD,
        untrackedMs: Long = 0L
    ) = attempt(
        iso, total / 30, total % 30, profile = profile, untrackedMs = untrackedMs
    )

    /** A full session whose rounds each took [seconds]. */
    private fun paced(iso: String, seconds: Int, durationMs: Long = 20 * 60_000L) =
        attempt(iso, 10, durationMs = durationMs, splits = List(10) { seconds * 1000L })

    @Test
    fun `categories list the most recent first`() {
        val list = listOf(
            scored("2026-08-01", 400), scored("2026-08-05", 300, knee),
            scored("2026-08-10", 410)
        )
        assertEquals(listOf<CindyProfile?>(CindyProfile.STANDARD, knee), Progress.categories(list))
    }

    @Test
    fun `a record is flagged when it is set`() {
        val list = listOf(400, 380, 420, 420, 450).mapIndexed { i, s ->
            scored("2026-08-0${i + 1}", s)
        }
        val s = Progress.scoreSeries(list, CindyProfile.STANDARD, null, zone)
        assertEquals(listOf(true, false, true, false, true), s.points.map { it.record })
        assertEquals(listOf(400.0, 400.0, 420.0, 420.0, 450.0), s.best)
    }

    @Test
    fun `a lower-bound score is plotted but never a record`() {
        val list = listOf(
            scored("2026-08-01", 400), scored("2026-08-02", 450, untrackedMs = 60_000L),
            scored("2026-08-03", 440)
        )
        val s = Progress.scoreSeries(list, CindyProfile.STANDARD, null, zone)
        assertEquals(listOf(true, false, false), s.points.map { it.record })
        assertEquals(listOf(false, true, false), s.points.map { it.lowerBound })
        assertEquals(listOf(400.0, 450.0, 450.0), s.best)
    }

    @Test
    fun `other categories stay off the line`() {
        val list = listOf(scored("2026-08-01", 400), scored("2026-08-02", 300, knee))
        val s = Progress.scoreSeries(list, CindyProfile.STANDARD, null, zone)
        assertEquals(listOf(400.0), s.points.map { it.value })
    }

    @Test
    fun `the range cuts points but remembers the whole history`() {
        val list = listOf(
            scored("2026-05-01", 500), scored("2026-09-01", 480), scored("2026-09-05", 490)
        )
        val from = ProgressRange.MONTH.start(today)
        val s = Progress.scoreSeries(list, CindyProfile.STANDARD, from, zone)
        assertEquals(listOf(480.0, 490.0), s.points.map { it.value })
        assertEquals(listOf(false, false), s.points.map { it.record })
        assertEquals(listOf(500.0, 500.0), s.best)
    }

    @Test
    fun `pace counts full sessions only and faster is better`() {
        val list = listOf(
            paced("2026-08-01", 70), paced("2026-08-02", 65), paced("2026-08-03", 68),
            paced("2026-08-04", 50, durationMs = 10 * 60_000L)
        )
        val s = Progress.paceSeries(list, CindyProfile.STANDARD, null, zone)
        assertEquals(listOf(70.0, 65.0, 68.0), s.points.map { it.value })
        assertEquals(listOf(true, true, false), s.points.map { it.record })
        assertEquals(listOf(70.0, 65.0, 65.0), s.best)
        assertTrue(s.lowerIsBetter)
    }

    @Test
    fun `weekly volume keeps empty weeks`() {
        val list = listOf(
            scored("2026-08-17", 400), scored("2026-08-19", 410), scored("2026-09-02", 420)
        )
        val v = Progress.weeklyVolume(list, null, today, zone, monday)
        assertEquals(listOf(810.0, 0.0, 420.0, 0.0), v.map { it.value })
        assertEquals(listOf(2, 0, 1, 0), v.map { it.sessions })
    }

    @Test
    fun `weekly volume starts at the range`() {
        val list = listOf(scored("2026-08-17", 400), scored("2026-09-02", 420))
        val v = Progress.weeklyVolume(list, LocalDate.of(2026, 8, 26), today, zone, monday)
        val first = LocalDate.of(2026, 8, 24).atStartOfDay(zone).toInstant().toEpochMilli()
        assertEquals(first, v.first().atMillis)
    }

    @Test
    fun `the summary compares this week with last`() {
        val list = listOf(
            scored("2026-09-07", 400), scored("2026-09-09", 420), scored("2026-09-01", 390)
        )
        val s = Progress.summary(list, today, zone, monday)
        assertEquals(Period(2, 820, 40 * 60_000L), s.thisWeek)
        assertEquals(Period(1, 390, 20 * 60_000L), s.lastWeek)
        assertEquals(Period(3, 1210, 60 * 60_000L), s.thisMonth)
    }

    @Test
    fun `the summary uses the locale's week`() {
        val list = listOf(scored("2026-09-06", 400))
        assertEquals(1, Progress.summary(list, today, zone, DayOfWeek.SUNDAY).thisWeek.sessions)
        assertEquals(1, Progress.summary(list, today, zone, monday).lastWeek.sessions)
        assertEquals(0, Progress.summary(list, today, zone, monday).thisWeek.sessions)
    }

    @Test
    fun `ticks land on round numbers`() {
        assertEquals(listOf(400.0, 450.0, 500.0, 550.0), Progress.niceTicks(410.0, 522.0))
        assertEquals(listOf(60.0, 65.0, 70.0, 75.0), Progress.niceTicks(62.0, 75.0))
        assertEquals(listOf(0.0, 1.0, 2.0, 3.0), Progress.niceTicks(0.0, 3.0))
    }

    @Test
    fun `a flat line still gets ticks`() {
        val t = Progress.niceTicks(500.0, 500.0)
        assertEquals(t.sorted(), t)
        assertTrue(t.any { it == 500.0 })
        assertTrue(t.size in 2..6)
    }

    @Test
    fun `the nearest point wins, ties go left`() {
        assertEquals(-1, Progress.nearestIndex(emptyList(), 3f))
        assertEquals(0, Progress.nearestIndex(listOf(10f), 99f))
        val xs = listOf(10f, 20f, 30f)
        assertEquals(0, Progress.nearestIndex(xs, 14f))
        assertEquals(0, Progress.nearestIndex(xs, 15f))
        assertEquals(1, Progress.nearestIndex(xs, 16f))
        assertEquals(0, Progress.nearestIndex(xs, -5f))
        assertEquals(2, Progress.nearestIndex(xs, 100f))
    }

    @Test
    fun `formats`() {
        assertEquals("1,490", Progress.formatReps(1490))
        assertEquals("0 min", Progress.formatClock(0L))
        assertEquals("42 min", Progress.formatClock(42 * 60_000L))
        assertEquals("1 h 02 min", Progress.formatClock(62 * 60_000L))
        assertEquals("+3", Progress.formatDelta(3))
        assertEquals("−2", Progress.formatDelta(-2))
        assertNull(Progress.formatDelta(0))
    }
}
