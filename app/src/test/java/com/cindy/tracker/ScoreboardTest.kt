package com.cindy.tracker

import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the camera screen's scoreboard prints: the figure ("3/5") and the line under it
 * ("Pull-ups · Round 2"), read the way a screen reads them, as text with spans.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ScoreboardTest {

    private val slash = 0x52EBEBF5
    private val target = 0x9EEBEBF5.toInt()

    private fun figure(c: String, t: String?) = Scoreboard.figure(c, t, slash, target) as Spanned

    private fun colourAt(text: Spanned, index: Int): Int? =
        text.getSpans(index, index + 1, ForegroundColorSpan::class.java).lastOrNull()?.foregroundColor

    @Test
    fun `the figure reads count, slash, target`() {
        assertEquals("3/5", figure("3", "/5").toString())
        assertEquals("12/15", figure("12", "/15").toString())
    }

    @Test
    fun `the count and the target are one size and one weight, and only the colour steps down`() {
        val text = figure("12", "/15")
        assertEquals("a span changes the size", 0, text.getSpans(0, text.length, AbsoluteSizeSpan::class.java).size)
        assertEquals("a span changes the size", 0, text.getSpans(0, text.length, RelativeSizeSpan::class.java).size)
        assertEquals("a span changes the weight", 0, text.getSpans(0, text.length, StyleSpan::class.java).size)
        assertEquals("a span changes the face", 0, text.getSpans(0, text.length, TypefaceSpan::class.java).size)
        // The count takes the view's own colour, so a banked rep can pulse it; the rest is quieter.
        assertEquals(null, colourAt(text, 0))
        assertEquals(slash, colourAt(text, 2))
        assertEquals(target, colourAt(text, 3))
        assertEquals(target, colourAt(text, 4))
    }

    @Test
    fun `with no target there is no slash`() {
        assertEquals("—", figure("—", null).toString())
        assertEquals("—", figure("—", "").toString())
    }

    @Test
    fun `the line reads the movement in sentence case, a middle dot, then the round`() {
        assertEquals("Pull-ups · Round 2", Scoreboard.line("PULL-UPS", 2).toString())
        assertEquals("Squats · Round 12", Scoreboard.line("SQUATS", 12).toString())
        assertEquals("Set up · Round 1", Scoreboard.line("SET UP", 1).toString())
    }

    @Test
    fun `tabular figures are asked for the round only`() {
        val text = Scoreboard.line("PUSH-UPS", 12) as Spanned
        val spans = text.getSpans(0, text.length, android.text.style.MetricAffectingSpan::class.java)
        assertEquals(1, spans.size)
        assertEquals("12", text.substring(text.getSpanStart(spans[0]), text.getSpanEnd(spans[0])))
    }

    @Test
    fun `a screen reader hears the movement and the round, not a dot`() {
        assertEquals("Pull-ups, round 2", Scoreboard.spokenLine("PULL-UPS", 2))
        assertFalse(Scoreboard.spokenLine("SQUATS", 3).contains('·'))
    }
}
