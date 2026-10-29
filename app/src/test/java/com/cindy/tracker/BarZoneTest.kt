package com.cindy.tracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a bar is learned from.
 *
 * A grip is about a shoulder's width and a shoulder is about one torso wide: on the recorded sessions
 * the wrists of a real hang were 0.6 to 1.0 torso apart. Four of them learned their bar at a moment
 * when one wrist was read on top of the other, 3 to 6 px apart, which put the centre of the bar on
 * one hand and left the other hand outside it for the rest of the session (see
 * [StuckCalibrationTest]).
 */
class BarZoneTest {

    private fun wrist(x: Float, y: Float = 300f) = Keypoint(x, y, 0.9f)

    @Test
    fun `a bar learned while one wrist was read on top of the other still holds the real grip`() {
        val zone = BarZone()
        // The hands' midpoint is where the wrists were read: both at x = 360, 1.5 px either side.
        zone.observeHang(handsX = 360f, handsY = 300f, halfGrip = 1.5f, torso = 80f)

        // The real grip: a shoulder's width, 0.8 of a torso, with the left hand off to the left.
        assertTrue(zone.holds(wrist(360f - 0.8f * 80f), wrist(360f), 80f))
    }

    @Test
    fun `the allowance for such a grip scales with the athlete`() {
        val zone = BarZone()
        zone.observeHang(handsX = 360f, handsY = 300f, halfGrip = 1.5f, torso = 40f)

        assertTrue("the same grip on an athlete half as big", zone.holds(wrist(360f - 0.8f * 40f), wrist(360f), 40f))
        assertFalse("but not a hand on the far side of the frame", zone.holds(wrist(100f), wrist(140f), 40f))
    }

    @Test
    fun `a grip that was seen wide is not widened further`() {
        val zone = BarZone()
        zone.observeHang(handsX = 360f, handsY = 300f, halfGrip = 60f, torso = 80f)

        assertTrue(zone.holds(wrist(300f), wrist(420f), 80f))
        // 60 px of grip and 0.6 of a torso either side: a hand 120 px out is past the bar.
        assertFalse(zone.holds(wrist(240f), wrist(480f), 80f))
    }
}
