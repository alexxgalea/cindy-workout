package com.cindy.tracker

import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [Calories.timeline] is the running total behind [Calories.estimate], drawn on the results
 * timeline. What must hold is that the two can never disagree about the figure, so most of this is
 * that equality over traces nobody chose by hand.
 */
class CaloriesTimelineTest {

    private val twentyMinutes = 20 * 60 * 1000L
    private val body = Body(70.0, 30, Sex.MALE)

    private fun trace(vararg samples: Pair<Long, Int>) = HeartRateTrace(
        startedAtMillis = 0L,
        samples = samples.map { HeartRateSample(it.first, it.second) },
        pauses = emptyList()
    )

    @Test
    fun `no weight or no clock gives no points, as estimate gives no number`() {
        assertTrue(Calories.timeline(300, twentyMinutes, Body(0.0), null).isEmpty())
        assertTrue(Calories.timeline(300, 0L, body, null).isEmpty())
    }

    @Test
    fun `without a trace it is the origin and the end, both estimated`() {
        val points = Calories.timeline(300, twentyMinutes, body, null)
        assertEquals(2, points.size)
        assertEquals(CaloriePoint(0L, 0.0, fromHeartRate = false), points[0])
        assertEquals(twentyMinutes, points[1].clockMs)
        assertFalse(points[1].fromHeartRate)
        assertEquals(Calories.estimate(300, twentyMinutes, body, null)!!.kcal, points[1].kcal.toInt())
    }

    @Test
    fun `a trace with no age on file stays on the reps, as estimate does`() {
        val noAge = Body(70.0, age = null, sex = Sex.MALE)
        val points = Calories.timeline(300, twentyMinutes, noAge, trace(0L to 150, 1_000L to 150))
        assertEquals(2, points.size)
        assertFalse(points.any { it.fromHeartRate })
        assertEquals(
            Calories.estimate(300, twentyMinutes, noAge, trace(0L to 150))!!.kcal,
            Math.round(points.last().kcal).toInt()
        )
    }

    @Test
    fun `a trace of nothing usable is the reps-only pair`() {
        val junk = trace(0L to 10, 1_000L to 300)
        val points = Calories.timeline(300, twentyMinutes, body, junk)
        assertEquals(2, points.size)
        assertFalse(points.last().fromHeartRate)
    }

    @Test
    fun `heart-rate stretches are flagged and the gaps between them are not`() {
        // 150 bpm for 3 s then silence until 10 s: the hold ends at 5 s, so 5..10 s is estimated.
        val points = Calories.timeline(300, 20_000L, body, trace(0L to 150, 10_000L to 150))
        assertEquals(
            listOf(
                0L to false,
                5_000L to true,
                10_000L to false,
                15_000L to true,
                20_000L to false
            ),
            points.map { it.clockMs to it.fromHeartRate }
        )
    }

    @Test
    fun `the first sample not at zero leaves an estimated lead-in`() {
        val points = Calories.timeline(300, 20_000L, body, trace(2_000L to 150, 3_000L to 150))
        assertEquals(listOf(0L, 2_000L, 3_000L, 8_000L, 20_000L), points.map { it.clockMs })
        assertEquals(
            listOf(false, false, true, true, false), points.map { it.fromHeartRate }
        )
    }

    @Test
    fun `it never goes down and never stands still`() {
        val random = Random(7)
        repeat(50) {
            val points = Calories.timeline(300, twentyMinutes, body, randomTrace(random))
            for (i in 1 until points.size) {
                assertTrue("clock must advance at $i", points[i].clockMs > points[i - 1].clockMs)
                assertTrue("kcal must not fall at $i", points[i].kcal >= points[i - 1].kcal)
            }
            assertEquals(0L, points.first().clockMs)
            assertEquals(twentyMinutes, points.last().clockMs)
        }
    }

    @Test
    fun `its last point rounds to the estimate over generated traces`() {
        val random = Random(2026)
        repeat(200) { n ->
            val reps = random.nextInt(0, 400)
            val activeMs = random.nextLong(30_000L, twentyMinutes)
            val b = when (n % 4) {
                0 -> Body(65.0 + n % 30, 25 + n % 40, Sex.FEMALE)
                1 -> Body(80.0, 41, Sex.MALE)
                2 -> Body(72.5, 33, Sex.UNSTATED)
                else -> Body(90.0, age = null, sex = null)
            }
            val t = if (n % 10 == 9) null else randomTrace(random, activeMs)
            val estimate = Calories.estimate(reps, activeMs, b, t)!!
            val points = Calories.timeline(reps, activeMs, b, t)
            assertEquals("run $n", estimate.kcal, Math.round(points.last().kcal).toInt())
            assertEquals("run $n", activeMs, points.last().clockMs)
            // And what it flags as measured is exactly what the estimate says the watch covered.
            var measured = 0L
            for (i in 1 until points.size) {
                if (points[i].fromHeartRate) measured += points[i].clockMs - points[i - 1].clockMs
            }
            assertEquals("run $n", estimate.heartRateMs, measured)
        }
    }

    @Test
    fun `duplicate and out-of-order samples do not break the equality`() {
        val t = trace(5_000L to 140, 1_000L to 150, 1_000L to 152, 5_000L to 141, 30_000L to 160)
        val estimate = Calories.estimate(250, 40_000L, body, t)!!
        val points = Calories.timeline(250, 40_000L, body, t)
        assertEquals(estimate.kcal, Math.round(points.last().kcal).toInt())
        for (i in 1 until points.size) assertTrue(points[i].clockMs > points[i - 1].clockMs)
    }

    /** Bursts of samples a second apart with silences of random length between them. */
    private fun randomTrace(random: Random, activeMs: Long = twentyMinutes): HeartRateTrace {
        val samples = mutableListOf<Pair<Long, Int>>()
        var at = random.nextLong(0L, 4_000L)
        while (at < activeMs + 2_000L) {
            samples += at to random.nextInt(25, 235)
            at += if (random.nextInt(10) == 0) random.nextLong(5_001L, 60_000L) else random.nextLong(500L, 2_500L)
        }
        return trace(*samples.toTypedArray())
    }
}
