package com.cindy.tracker

import java.util.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two knobs [RepCounter] grew for the heels-flat squat, and the promise that turning neither
 * changes anything else.
 *
 * Pull-ups, push-ups and air squats are counted by the same class, and their parity trace is what
 * keeps the desktop harness honest. So the first test is the one that matters most: a counter
 * given the defaults explicitly must be indistinguishable from one built the way every caller
 * built it before.
 */
class RepCounterMarginsTest {

    /** Feeds one value repeatedly so the smoother settles, returning how many reps were booked. */
    private fun RepCounter.hold(value: Float, startMs: Long, frames: Int = 10): Int {
        var reps = 0
        for (i in 0 until frames) if (update(value, startMs + i * 100L)) reps++
        return reps
    }

    /** The sort of band a heels-flat squat is counted against. */
    private fun heelsFlat(bottomMargin: Float = 0.6f, minTravel: Float = 35f) = RepCounter(
        120f, 158f, minRepMs = 350L, minRange = 35f,
        bottomMargin = bottomMargin, minTravel = minTravel
    )

    @Test
    fun `the defaults, given explicitly, count exactly what the old constructor counted`() {
        val old = RepCounter(100f, 158f, minRepMs = 350L, minRange = 55f)
        val explicit = RepCounter(
            100f, 158f, minRepMs = 350L, minRange = 55f, bottomMargin = 0.30f, minTravel = 0f
        )

        // A long, untidy run: swings of every size, noise on top, and stretches of standing still.
        val noise = Random(7)
        var now = 0L
        var booked = 0
        for (set in 0 until 40) {
            val low = 60f + noise.nextInt(60)
            val high = 140f + noise.nextInt(40)
            for (step in 0 until 30) {
                val t = step / 29f
                val wave = if (t < 0.5f) t * 2f else (1f - t) * 2f
                val raw = high - (high - low) * wave + (noise.nextFloat() - 0.5f) * 6f
                val a = old.update(raw, now)
                val b = explicit.update(raw, now)
                assertEquals("set $set step $step: a rep booked differently", a, b)
                assertEquals(old.count, explicit.count)
                assertEquals(old.phase, explicit.phase)
                assertEquals(old.learnedRange, explicit.learnedRange, 0f)
                assertEquals(old.smoothed, explicit.smoothed, 0f)
                if (a) booked++
                now += 70L
            }
        }
        assertTrue("the run booked nothing, so it proved nothing", booked > 10)
    }

    /** A wide band, taught by one deep rep, for the tests below to work against. */
    private fun RepCounter.afterOneDeepRep(): Long {
        var t = 0L
        hold(175f, t); t += 1000
        hold(60f, t); t += 1000
        hold(175f, t); t += 1000
        assertEquals("the deep rep should have counted", 1, count)
        return t
    }

    @Test
    fun `a minimum travel refuses a wobble that a wide band would otherwise accept`() {
        // After a deep rep the band is about 115 degrees wide, so a bottom zone of 60% arms below
        // about 129 and the top zone starts near 140: a shake between the two is 12 degrees.
        val without = heelsFlat(minTravel = 0f)
        val with = heelsFlat(minTravel = 35f)
        var t = without.afterOneDeepRep()
        with.afterOneDeepRep()

        repeat(4) {
            without.hold(126f, t); with.hold(126f, t); t += 1000
            without.hold(146f, t); with.hold(146f, t); t += 1000
        }

        assertTrue("without a floor the wobble counts", without.count > 1)
        assertEquals("with one it does not", 1, with.count)
    }

    @Test
    fun `a wider bottom zone arms a rep that stops higher than the band's deepest`() {
        val narrow = heelsFlat(bottomMargin = 0.30f)
        val wide = heelsFlat(bottomMargin = 0.60f)
        var t = narrow.afterOneDeepRep()
        wide.afterOneDeepRep()

        // 120 is well above the bottom 30% of a band that reaches down to 60, and inside 60%.
        repeat(3) {
            narrow.hold(120f, t); wide.hold(120f, t); t += 1000
            narrow.hold(175f, t); wide.hold(175f, t); t += 1000
        }

        assertEquals("a rep that never reached the narrow bottom does not arm", 1, narrow.count)
        assertEquals("the wider zone counts all three", 4, wide.count)
    }

    @Test
    fun `a heels-flat counter still refuses a climb short of its minimum after a shallow start`() {
        // No deep rep to widen the band: shallow reps teach a narrow one, and 25 degrees of
        // travel is under the floor however the zones fall.
        val c = heelsFlat()
        var t = 0L
        repeat(6) {
            c.hold(150f, t); t += 1000
            c.hold(175f, t); t += 1000
        }
        assertEquals(0, c.count)
    }
}
