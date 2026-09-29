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

    private fun scorePoints(vararg a: Attempt) =
        Progress.scoreSeries(a.toList(), CindyProfile.STANDARD, null, zone).points

    private fun describeScore(points: List<ProgressPoint>, i: Int) =
        Progress.describe(ProgressMetric.SCORE, points, i, zone)

    @Test
    fun `describe a first score has no comparison`() {
        val points = scorePoints(scored("2026-09-01", 400))
        val (head, detail) = describeScore(points, 0)
        assertEquals("1 Sep · 13 + 10", head)
        assertEquals("400 reps · personal record · first in this range", detail)
    }

    @Test
    fun `describe a score that beat the session before`() {
        val points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 414))
        assertEquals(
            "414 reps · personal record · +14 on the session before",
            describeScore(points, 1).second
        )
    }

    @Test
    fun `describe a score below the session before uses words`() {
        val points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 394))
        assertEquals("394 reps · 6 below the session before", describeScore(points, 1).second)
    }

    @Test
    fun `describe a level score`() {
        val points = scorePoints(scored("2026-09-01", 400), scored("2026-09-03", 400))
        assertEquals("400 reps · level with the session before", describeScore(points, 1).second)
    }

    @Test
    fun `describe a lower bound says the camera lost you and is no record`() {
        val points = scorePoints(
            scored("2026-09-01", 300), scored("2026-09-03", 350, untrackedMs = 60_000L)
        )
        assertEquals(
            "350 reps · at least — camera lost you · +50 on the session before",
            describeScore(points, 1).second
        )
    }

    @Test
    fun `describe pace says how much faster`() {
        val points = Progress.paceSeries(
            listOf(paced("2026-09-01", 70), paced("2026-09-03", 66)),
            CindyProfile.STANDARD, null, zone
        ).points
        val (head, detail) = Progress.describe(ProgressMetric.PACE, points, 1, zone)
        assertEquals("3 Sep · 1:06 a round", head)
        assertEquals("fastest yet · 4s faster than the session before", detail)
    }

    @Test
    fun `describe pace says how much slower and has no record flag`() {
        val points = Progress.paceSeries(
            listOf(paced("2026-09-01", 60), paced("2026-09-03", 63)),
            CindyProfile.STANDARD, null, zone
        ).points
        assertEquals(
            "3s slower than the session before",
            Progress.describe(ProgressMetric.PACE, points, 1, zone).second
        )
    }

    @Test
    fun `describe pace can be the same or the first`() {
        val points = Progress.paceSeries(
            listOf(paced("2026-09-01", 60), paced("2026-09-03", 60)),
            CindyProfile.STANDARD, null, zone
        ).points
        assertEquals(
            "fastest yet · first in this range",
            Progress.describe(ProgressMetric.PACE, points, 0, zone).second
        )
        assertEquals(
            "same pace as the session before",
            Progress.describe(ProgressMetric.PACE, points, 1, zone).second
        )
    }

    @Test
    fun `describe a volume bar names the week and counts sessions`() {
        val bars = Progress.weeklyVolume(
            listOf(scored("2026-09-07", 400), scored("2026-09-08", 300)),
            LocalDate.of(2026, 9, 7), today, zone, monday
        )
        assertEquals(
            "Week of 7 Sep" to "700 reps · 2 sessions",
            Progress.describe(ProgressMetric.VOLUME, bars, 0, zone)
        )
        val one = Progress.weeklyVolume(
            listOf(scored("2026-09-07", 1200)), LocalDate.of(2026, 9, 7), today, zone, monday
        )
        assertEquals(
            "1,200 reps · 1 session",
            Progress.describe(ProgressMetric.VOLUME, one, 0, zone).second
        )
    }

    @Test
    fun `overview of nothing`() {
        for (m in ProgressMetric.values()) {
            assertEquals("No sessions in this range" to "", Progress.overview(m, emptyList()))
        }
    }

    @Test
    fun `overview of scores skips a lower bound unless all are`() {
        val mixed = scorePoints(
            scored("2026-09-01", 300), scored("2026-09-03", 500, untrackedMs = 60_000L)
        )
        assertEquals(
            "Best 10" to "2 sessions in this range",
            Progress.overview(ProgressMetric.SCORE, mixed)
        )
        val only = scorePoints(scored("2026-09-03", 500, untrackedMs = 60_000L))
        assertEquals(
            "Best 16 + 20" to "1 session in this range",
            Progress.overview(ProgressMetric.SCORE, only)
        )
    }

    @Test
    fun `overview of pace names the fastest round`() {
        val points = Progress.paceSeries(
            listOf(paced("2026-09-01", 70), paced("2026-09-03", 66), paced("2026-09-05", 68)),
            CindyProfile.STANDARD, null, zone
        ).points
        assertEquals(
            "Best 1:06 a round" to "3 full sessions in this range",
            Progress.overview(ProgressMetric.PACE, points)
        )
        assertEquals(
            "1 full session in this range",
            Progress.overview(ProgressMetric.PACE, points.take(1)).second
        )
    }

    @Test
    fun `overview of volume totals the bars`() {
        val bars = Progress.weeklyVolume(
            listOf(scored("2026-08-31", 400), scored("2026-09-08", 900)),
            LocalDate.of(2026, 8, 31), today, zone, monday
        )
        assertEquals(
            "1,300 reps" to "2 sessions in this range",
            Progress.overview(ProgressMetric.VOLUME, bars)
        )
    }
}
