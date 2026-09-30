package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StravaHeartRateTest {

    private val start = 1_700_000_000_000L

    @Test
    fun `with no pauses the wall clock is just the start plus the clock reading`() {
        val trace = HeartRateTrace(start, samples = emptyList(), pauses = emptyList())
        assertEquals(start + 3_000L, StravaHeartRate.wallMillis(trace, 3_000L))
    }

    @Test
    fun `samples on either side of two pauses keep their true wall offsets`() {
        val trace = HeartRateTrace(
            startedAtMillis = start,
            samples = listOf(
                HeartRateSample(3_000L, 90),
                HeartRateSample(7_000L, 120),
                HeartRateSample(12_000L, 140)
            ),
            pauses = listOf(
                HeartRatePause(atClockMs = 5_000L, lengthMs = 2_000L),
                HeartRatePause(atClockMs = 10_000L, lengthMs = 3_000L)
            )
        )
        // Before either pause: no pause time to add back in.
        assertEquals(start + 3_000L, StravaHeartRate.wallMillis(trace, 3_000L))
        // Between the two pauses: only the first has happened by then.
        assertEquals(start + 7_000L + 2_000L, StravaHeartRate.wallMillis(trace, 7_000L))
        // After both pauses: both have happened by then.
        assertEquals(start + 12_000L + 2_000L + 3_000L, StravaHeartRate.wallMillis(trace, 12_000L))
    }

    @Test
    fun `a sample exactly at a pause's clock reading still counts that pause`() {
        val trace = HeartRateTrace(
            startedAtMillis = start,
            samples = emptyList(),
            pauses = listOf(HeartRatePause(atClockMs = 5_000L, lengthMs = 2_000L))
        )
        // The formula's <=, not <: right at the pause's own moment, the pause already counts.
        assertEquals(start + 5_000L + 2_000L, StravaHeartRate.wallMillis(trace, 5_000L))
        // A tick earlier, it does not yet.
        assertEquals(start + 4_999L, StravaHeartRate.wallMillis(trace, 4_999L))
    }

    @Test
    fun `points reports each sample's seconds from the given start, floored`() {
        val trace = HeartRateTrace(
            startedAtMillis = start,
            samples = listOf(HeartRateSample(0L, 90), HeartRateSample(3_500L, 110)),
            pauses = emptyList()
        )
        assertEquals(
            listOf(HrPoint(0, 90), HrPoint(3, 110)),
            StravaHeartRate.points(trace, startMillis = start)
        )
    }

    @Test
    fun `points keeps true wall offsets across a pause, not just the clock reading`() {
        val trace = HeartRateTrace(
            startedAtMillis = start,
            samples = listOf(HeartRateSample(3_000L, 90), HeartRateSample(7_000L, 120)),
            pauses = listOf(HeartRatePause(atClockMs = 5_000L, lengthMs = 10_000L))
        )
        val points = StravaHeartRate.points(trace, startMillis = start)
        assertEquals(3, points[0].secondsFromStart)
        // 7s on the clock, plus the 10s pause that had already happened by then.
        assertEquals(17, points[1].secondsFromStart)
    }

    @Test
    fun `an empty trace gives an empty list`() {
        val trace = HeartRateTrace(start, samples = emptyList(), pauses = emptyList())
        assertTrue(StravaHeartRate.points(trace, startMillis = start).isEmpty())
    }
}
