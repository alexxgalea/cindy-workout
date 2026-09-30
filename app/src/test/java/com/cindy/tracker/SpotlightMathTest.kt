package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SpotlightMathTest {

    private val gap = 14f
    private val margin = 16f
    private val screen = 2400f
    private val card = 300f

    private fun top(targetTop: Float, targetBottom: Float, caption: Float = card, height: Float = screen) =
        SpotlightMath.captionTop(targetTop, targetBottom, caption, height, gap, margin)

    @Test
    fun `the caption goes below a target near the top, with a gap`() {
        assertEquals(200f + gap, top(100f, 200f), 0f)
    }

    @Test
    fun `it goes above a target too low to have room underneath`() {
        // The target ends at 2300, so the card would run off the bottom. Above it instead.
        assertEquals(2200f - gap - card, top(2200f, 2300f), 0f)
    }

    @Test
    fun `below is kept right up to the last pixel that fits`() {
        val lowest = screen - margin - card
        val fits = lowest - gap          // a target bottom that leaves the card exactly on the margin
        assertEquals(fits + gap, top(fits - 100f, fits), 0f)
        // One pixel lower and it no longer fits below, so it moves above.
        assertEquals(fits - 99f - gap - card, top(fits - 99f, fits + 1f), 0f)
    }

    @Test
    fun `above is kept right down to the margin`() {
        // A target whose top leaves the card exactly on the top margin.
        val targetTop = margin + card + gap
        assertEquals(margin, top(targetTop, screen - 10f), 0f)
    }

    @Test
    fun `on a short screen where neither side has room the caption stays on it`() {
        // 500 tall: a 300 card fits only between 16 and 184 from the bottom edge.
        val y = top(200f, 300f, height = 500f)
        assertEquals(500f - margin - card, y, 0f)
        assertTrue(y >= margin)
        assertTrue(y + card <= 500f - margin)
    }

    @Test
    fun `a caption taller than the screen starts at the margin rather than above it`() {
        assertEquals(margin, top(100f, 200f, caption = 900f, height = 600f), 0f)
    }

    @Test
    fun `the caption is never placed off either end of the screen`() {
        for (targetTop in listOf(0f, 50f, 400f, 1200f, 2000f, 2350f)) {
            val y = top(targetTop, targetTop + 100f)
            assertTrue("top $targetTop: $y", y >= margin)
            assertTrue("top $targetTop: ${y + card}", y + card <= screen - margin)
        }
    }

    @Test
    fun `it never lands on the target when there is room on either side`() {
        for (targetTop in listOf(0f, 50f, 400f, 1200f, 1800f, 2000f, 2300f)) {
            val targetBottom = targetTop + 100f
            val y = top(targetTop, targetBottom)
            val overlaps = y < targetBottom && y + card > targetTop
            assertTrue("target $targetTop..$targetBottom, card at $y", !overlaps)
        }
    }
}
