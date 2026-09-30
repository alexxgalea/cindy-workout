package com.cindy.tracker

import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The heart-rate half of [Calories]. `burned()`/`met()` and their regression coverage in
 * [CaloriesTest] are untouched — this only tests what `estimate()` and `keytelKcalPerMinute()`
 * add on top.
 */
class CaloriesHeartRateTest {

    private val twentyMinutes = 20 * 60 * 1000L
    private val tolerance = 1e-4

    private fun body(kg: Double, age: Int?, sex: Sex?) = Body(kg, age, sex)

    // ── Keytel kcal/min, reference values computed independently of this implementation ───────

    @Test
    fun `keytel kcal per minute matches the reference table`() {
        assertEquals(14.222060, Calories.keytelKcalPerMinute(150, body(70.0, 30, Sex.MALE)), tolerance)
        assertEquals(9.875669, Calories.keytelKcalPerMinute(150, body(60.0, 30, Sex.FEMALE)), tolerance)
        assertEquals(11.897933, Calories.keytelKcalPerMinute(150, body(70.0, 30, Sex.UNSTATED)), tolerance)
        assertEquals(18.195053, Calories.keytelKcalPerMinute(170, body(80.0, 40, Sex.MALE)), tolerance)
        assertEquals(6.429804, Calories.keytelKcalPerMinute(120, body(65.0, 25, Sex.FEMALE)), tolerance)
        // Below the fit's range the raw equation undershoots resting metabolism; the floor catches it.
        assertEquals(1.225, Calories.keytelKcalPerMinute(60, body(70.0, 30, Sex.MALE)), tolerance)
        assertEquals(1.05, Calories.keytelKcalPerMinute(60, body(60.0, 30, Sex.FEMALE)), tolerance)
    }

    // ── estimate() ──────────────────────────────────────────────────────────────────────────

    @Test
    fun `(i) no trace matches burned exactly`() {
        val b = body(70.0, 30, Sex.MALE)
        val est = Calories.estimate(300, twentyMinutes, b, trace = null)!!
        assertEquals(196, est.kcal)
        assertEquals(Calories.burned(300, twentyMinutes, 70.0), est.kcal)
        assertEquals(0L, est.heartRateMs)
        assertEquals(twentyMinutes, est.estimatedMs)
        assertFalse(est.usedHeartRate)
    }

    @Test
    fun `(ii) a trace with age missing behaves as if there were none`() {
        val b = body(70.0, age = null, sex = Sex.MALE)
        val trace = HeartRateTrace(0L, listOf(HeartRateSample(0L, 150)), emptyList())
        val est = Calories.estimate(300, twentyMinutes, b, trace)!!
        assertEquals(Calories.burned(300, twentyMinutes, 70.0), est.kcal)
        assertEquals(0L, est.heartRateMs)
    }

    @Test
    fun `(iii) 1 Hz heart rate covering the whole workout`() {
        val b = body(70.0, 30, Sex.MALE)
        val samples = (0 until 1200).map { HeartRateSample(it * 1000L, 150) }
        val trace = HeartRateTrace(0L, samples, emptyList())
        val est = Calories.estimate(300, twentyMinutes, b, trace)!!
        assertEquals(284, est.kcal)
        assertEquals(twentyMinutes, est.heartRateMs)
        assertEquals(0L, est.estimatedMs)
    }

    @Test
    fun `(iv) heart rate only for the first ten minutes`() {
        val b = body(70.0, 30, Sex.MALE)
        // 1 Hz from clock 0 to 595_000; the last sample then holds for MAX_HOLD_MS, landing the
        // covered window exactly on the ten-minute mark.
        val samples = (0..595).map { HeartRateSample(it * 1000L, 150) }
        val trace = HeartRateTrace(0L, samples, emptyList())
        val est = Calories.estimate(300, twentyMinutes, b, trace)!!
        assertEquals(240, est.kcal)
        assertEquals(600_000L, est.heartRateMs)
        assertEquals(600_000L, est.estimatedMs)
    }

    @Test
    fun `(v) a gap wider than the hold window is estimated past the hold`() {
        val b = body(70.0, 30, Sex.MALE)
        val activeMs = 25_000L
        val trace = HeartRateTrace(
            0L,
            listOf(HeartRateSample(0L, 150), HeartRateSample(20_000L, 150)),
            emptyList()
        )
        val est = Calories.estimate(totalReps = 0, activeMs, b, trace)!!
        // Each sample holds for MAX_HOLD_MS; the 20s gap between them leaves 15s uncovered.
        assertEquals(2 * Calories.MAX_HOLD_MS, est.heartRateMs)
        assertEquals(15_000L, est.estimatedMs)

        val expectedKcal = (
            Calories.keytelKcalPerMinute(150, b) * (2 * Calories.MAX_HOLD_MS / 60_000.0) +
                Calories.met(0, activeMs) * 3.5 * b.weightKg / 200.0 * (15_000L / 60_000.0)
            ).roundToInt()
        assertEquals(expectedKcal, est.kcal)
    }

    @Test
    fun `(vi) samples beyond activeMs are ignored`() {
        val b = body(70.0, 30, Sex.MALE)
        val activeMs = 10_000L
        val trace = HeartRateTrace(
            0L,
            listOf(HeartRateSample(0L, 150), HeartRateSample(50_000L, 150)),
            emptyList()
        )
        val est = Calories.estimate(0, activeMs, b, trace)!!
        // Only the sample inside [0, activeMs) counts, and it holds for MAX_HOLD_MS.
        assertEquals(Calories.MAX_HOLD_MS, est.heartRateMs)
        assertEquals(activeMs - Calories.MAX_HOLD_MS, est.estimatedMs)
    }

    @Test
    fun `(vii) an implausible reading is ignored`() {
        val b = body(70.0, 30, Sex.MALE)
        val activeMs = 10_000L
        val trace = HeartRateTrace(0L, listOf(HeartRateSample(0L, 250)), emptyList())
        val est = Calories.estimate(0, activeMs, b, trace)!!
        assertEquals(0L, est.heartRateMs)
        assertEquals(activeMs, est.estimatedMs)
        assertEquals(Calories.burned(0, activeMs, 70.0), est.kcal)
    }

    @Test
    fun `(viii) no weight or no clock yields null`() {
        val b = body(70.0, 30, Sex.MALE)
        assertNull(Calories.estimate(300, twentyMinutes, body(0.0, 30, Sex.MALE), trace = null))
        assertNull(Calories.estimate(300, 0L, b, trace = null))
    }
}
