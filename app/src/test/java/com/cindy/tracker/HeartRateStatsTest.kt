package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateStatsTest {

    private val twentyMinutes = 20 * 60 * 1000L

    private fun trace(vararg samples: Pair<Long, Int>) = HeartRateTrace(
        startedAtMillis = 0L,
        samples = samples.map { HeartRateSample(it.first, it.second) },
        pauses = emptyList()
    )

    /** A reading a second for [seconds] seconds from [fromSecond], all at [bpm]. */
    private fun steady(fromSecond: Int, seconds: Int, bpm: Int) =
        (fromSecond until fromSecond + seconds).map { it * 1000L to bpm }

    private fun roundsOf(vararg ends: Long): List<RoundSpan> {
        var start = 0L
        return ends.mapIndexed { i, end -> RoundSpan(i + 1, start, end, complete = true).also { start = end } }
    }

    private fun summary(t: HeartRateTrace?, duration: Long = twentyMinutes, rounds: List<RoundSpan> = emptyList(), age: Int? = 30) =
        HeartRateStats.of(t, duration, rounds, age)

    // ── coverage, average, maximum ──────────────────────────────────────────────────────────

    @Test
    fun `no trace, or nothing usable in it, says nothing`() {
        assertNull(summary(null))
        assertNull(summary(trace()))
        assertNull(summary(trace(0L to 10, 1_000L to 300)))
        assertNull(summary(trace(0L to 150), duration = 0L))
    }

    @Test
    fun `a reading holds until the next one, so the average is weighted by time`() {
        // 100 bpm for 4 s, then 160 bpm for the 5 s hold: (100 x 4 + 160 x 5) / 9.
        val s = summary(trace(0L to 100, 4_000L to 160), duration = 60_000L)!!
        assertEquals(9_000L, s.coveredMs)
        assertEquals(Math.round((400.0 + 800.0) / 9.0).toInt(), s.avgBpm)
        assertEquals(160, s.maxBpm)
    }

    @Test
    fun `an average of readings alone would be wrong where the spacing is uneven`() {
        // Ten quick 180s then one lone 100: by count the mean is 172, by time it is far lower.
        val samples = (0 until 10).map { it * 100L to 180 } + (1_000L to 100)
        val s = summary(trace(*samples.toTypedArray()), duration = 60_000L)!!
        // 1 s at 180, then 5 s at 100.
        assertEquals(Math.round((180.0 * 1 + 100.0 * 5) / 6.0).toInt(), s.avgBpm)
    }

    @Test
    fun `a gap wider than the hold is not covered and not averaged in`() {
        val s = summary(trace(0L to 150, 60_000L to 150), duration = 120_000L)!!
        assertEquals(10_000L, s.coveredMs)
        assertEquals(150, s.avgBpm)
    }

    @Test
    fun `a reading never covers past the end of the clock`() {
        val s = summary(trace(58_000L to 150), duration = 60_000L)!!
        assertEquals(2_000L, s.coveredMs)
    }

    @Test
    fun `readings outside the clock or outside a plausible range are ignored`() {
        val s = summary(trace(0L to 150, 2_000L to 29, 3_000L to 231, 70_000L to 190), duration = 60_000L)!!
        assertEquals(150, s.maxBpm)
        assertEquals(5_000L, s.coveredMs)
    }

    @Test
    fun `duplicate and out-of-order readings are sorted and do not double count`() {
        val s = summary(trace(3_000L to 140, 1_000L to 120, 1_000L to 130), duration = 60_000L)!!
        // 1..3 s is held by the later duplicate (2 s), and the 140 at 3 s holds for the full 5 s.
        assertEquals(2_000L + 5_000L, s.coveredMs)
        assertEquals(140, s.maxBpm)
    }

    // ── Tanaka and the zone boundaries ──────────────────────────────────────────────────────

    @Test
    fun `the estimated maximum is Tanaka, 208 minus 0·7 times age, rounded`() {
        assertEquals(187, HeartRateStats.estimatedMax(30))
        assertEquals(181, HeartRateStats.estimatedMax(38)) // 181.4
        assertEquals(178, HeartRateStats.estimatedMax(43)) // 177.9
        assertEquals(138, HeartRateStats.estimatedMax(100))
    }

    @Test
    fun `zone edges sit exactly on 60, 70, 80 and 90 percent of the maximum`() {
        // Age 30: max 187, so the edges are 112.2, 130.9, 149.6 and 168.3.
        val max = 187
        assertEquals(HeartZone.WARM_UP, HeartRateStats.zoneOf(112, max))
        assertEquals(HeartZone.EASY, HeartRateStats.zoneOf(113, max))
        assertEquals(HeartZone.EASY, HeartRateStats.zoneOf(130, max))
        assertEquals(HeartZone.AEROBIC, HeartRateStats.zoneOf(131, max))
        assertEquals(HeartZone.AEROBIC, HeartRateStats.zoneOf(149, max))
        assertEquals(HeartZone.THRESHOLD, HeartRateStats.zoneOf(150, max))
        assertEquals(HeartZone.THRESHOLD, HeartRateStats.zoneOf(168, max))
        assertEquals(HeartZone.MAXIMUM, HeartRateStats.zoneOf(169, max))
    }

    @Test
    fun `a share that lands exactly on an edge belongs to the zone above it`() {
        // Max 150: 60% is 90, 70% is 105, 80% is 120, 90% is 135 — all whole numbers.
        assertEquals(HeartZone.WARM_UP, HeartRateStats.zoneOf(89, 150))
        assertEquals(HeartZone.EASY, HeartRateStats.zoneOf(90, 150))
        assertEquals(HeartZone.AEROBIC, HeartRateStats.zoneOf(105, 150))
        assertEquals(HeartZone.THRESHOLD, HeartRateStats.zoneOf(120, 150))
        assertEquals(HeartZone.MAXIMUM, HeartRateStats.zoneOf(135, 150))
    }

    @Test
    fun `a reading above the estimated maximum is still the top zone`() {
        assertEquals(HeartZone.MAXIMUM, HeartRateStats.zoneOf(200, 187))
    }

    @Test
    fun `each zone says the beats per minute it spans, with no gap or overlap`() {
        val s = summary(trace(0L to 150), age = 30)!!
        val zones = s.zones!!
        assertEquals(187, s.estimatedMaxBpm)
        assertEquals(
            listOf<Pair<Int?, Int?>>(null to 112, 113 to 130, 131 to 149, 150 to 168, 169 to null),
            zones.map { it.fromBpm to it.toBpm }
        )
        // Every whole bpm falls in exactly the zone whose printed range holds it.
        for (bpm in 30..230) {
            val z = HeartRateStats.zoneOf(bpm, 187)
            val range = zones[z.ordinal]
            assertTrue("$bpm", range.fromBpm == null || bpm >= range.fromBpm)
            assertTrue("$bpm", range.toBpm == null || bpm <= range.toBpm)
        }
    }

    @Test
    fun `time is put in the zone each reading was in`() {
        // Age 30: 100 bpm is warm-up, 160 is threshold, 175 maximum.
        val s = summary(
            trace(0L to 100, 10_000L to 160, 20_000L to 175, 25_000L to 175),
            duration = 60_000L
        )!!
        val ms = s.zones!!.associate { it.zone to it.ms }
        assertEquals(5_000L, ms[HeartZone.WARM_UP])
        assertEquals(5_000L, ms[HeartZone.THRESHOLD])
        assertEquals(10_000L, ms[HeartZone.MAXIMUM])
        assertEquals(0L, ms[HeartZone.EASY])
        assertEquals(s.coveredMs, s.zones!!.sumOf { it.ms })
    }

    // ── the verdict ─────────────────────────────────────────────────────────────────────────

    @Test
    fun `the verdict names the zone that held the most time`() {
        val t = trace(*(steady(0, 100, 100) + steady(100, 400, 160)).toTypedArray())
        val s = summary(t, duration = 600_000L)!!
        assertEquals("Longest in Z4 Threshold: 6:44 of the 8:24 your watch covered.", s.verdict)
    }

    @Test
    fun `a tie goes to the harder zone`() {
        val t = trace(*(steady(0, 60, 100) + steady(60, 60, 160)).toTypedArray())
        val s = summary(t, duration = 600_000L)!!
        assertTrue(s.verdict!!.startsWith("Longest in Z4 Threshold"))
    }

    // ── no age ──────────────────────────────────────────────────────────────────────────────

    @Test
    fun `without an age there are no zones, no maximum and no verdict, but the rest stands`() {
        val s = summary(trace(0L to 150, 5_000L to 170), age = null)!!
        assertNull(s.zones)
        assertNull(s.estimatedMaxBpm)
        assertNull(s.verdict)
        assertEquals(170, s.maxBpm)
        assertEquals(10_000L, s.coveredMs)
    }

    // ── the hardest round ───────────────────────────────────────────────────────────────────

    @Test
    fun `the hardest round is the highest time-weighted average`() {
        val t = trace(
            *(steady(0, 60, 140) + steady(60, 60, 170) + steady(120, 60, 155)).toTypedArray()
        )
        val s = summary(t, duration = 180_000L, rounds = roundsOf(60_000L, 120_000L, 180_000L))!!
        assertEquals(HardestRound(2, 170, 60_000L), s.hardestRound)
    }

    @Test
    fun `a round the watch saw for under thirty seconds cannot be the hardest`() {
        // Round 2 averages the most but only 10 s of it was heard.
        val t = trace(*(steady(0, 60, 140) + steady(60, 10, 200)).toTypedArray())
        val s = summary(t, duration = 120_000L, rounds = roundsOf(60_000L, 120_000L))!!
        assertEquals(1, s.hardestRound!!.number)
    }

    @Test
    fun `exactly thirty seconds is enough`() {
        val t = trace(*(steady(0, 60, 140) + steady(60, 26, 200)).toTypedArray())
        val s = summary(t, duration = 120_000L, rounds = roundsOf(60_000L, 120_000L))!!
        // 26 readings a second apart, the last held for the full five seconds: 25 + 5.
        assertEquals(HardestRound(2, 200, 30_000L), s.hardestRound)
    }

    @Test
    fun `a reading that straddles a round end is shared between the two`() {
        val t = trace(0L to 100, 58_000L to 180, 120_000L to 100)
        // 180 bpm holds 58..63 s: 2 s in round 1, 3 s in round 2. Neither has 30 s.
        val s = summary(t, duration = 180_000L, rounds = roundsOf(60_000L, 120_000L, 180_000L))!!
        assertNull(s.hardestRound)
    }

    @Test
    fun `equal rounds go to the earlier one`() {
        val t = trace(*(steady(0, 60, 150) + steady(60, 60, 150)).toTypedArray())
        val s = summary(t, duration = 120_000L, rounds = roundsOf(60_000L, 120_000L))!!
        assertEquals(1, s.hardestRound!!.number)
    }

    @Test
    fun `no rounds means no hardest round`() {
        assertNull(summary(trace(*steady(0, 60, 150).toTypedArray()), duration = 60_000L)!!.hardestRound)
        assertNotNull(summary(trace(*steady(0, 60, 150).toTypedArray()), duration = 60_000L))
    }
}
