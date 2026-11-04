package com.cindy.tracker

import java.util.Random
import kotlin.math.tan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Finding the bar in the picture, from the hand.
 *
 * The first fixture is a real frame (a binary PGM): the fold-out wall bars of the gym the sessions were recorded
 * in, with nobody in front of them (a crop of a screen recording, 340 x 110, x from 180 and y from
 * 330 in the recording). There the bar is a thin white tube on a white wall, tilted about seven
 * degrees, with three more rails a rail's width below it, which is what makes picking the held one
 * the whole difficulty. The numbers are what was measured on the full frame: the top rail crosses
 * x = 155 of the crop at y = 40, the next at 59, the next at 81.
 */
class RailFinderTest {

    /** The fixture is a binary PGM (P5): "P5", width and height, 255, then the pixels. */
    private fun wallBars(): Luma {
        val bytes = javaClass.getResourceAsStream("/rail/wall-bars-empty.pgm")!!.readBytes()
        var pos = 0
        fun token(): String {
            while (bytes[pos].toInt().toChar().isWhitespace()) pos++
            val start = pos
            while (!bytes[pos].toInt().toChar().isWhitespace()) pos++
            return String(bytes, start, pos - start)
        }
        check(token() == "P5")
        val w = token().toInt()
        val h = token().toInt()
        token()
        pos++
        return Luma(w, h, bytes.copyOfRange(pos, pos + w * h))
    }

    /** A wall of grey noise with bright tilted rails of [thickness] px, at [ys] where x = [atX]. */
    private fun synthetic(
        ys: List<Float>,
        degrees: Float,
        atX: Float = 150f,
        thickness: Float = 5f,
        width: Int = 300,
        height: Int = 140,
        seed: Long = 7
    ): Luma {
        val rnd = Random(seed)
        val px = ByteArray(width * height)
        val slope = tan(Math.toRadians(degrees.toDouble())).toFloat()
        for (y in 0 until height) for (x in 0 until width) {
            var v = 140f + (rnd.nextFloat() - 0.5f) * 8f
            for (r in ys) {
                if (kotlin.math.abs(y - (r + slope * (x - atX))) < thickness / 2) v = 235f
            }
            px[y * width + x] = v.toInt().coerceIn(0, 255).toByte()
        }
        return Luma(width, height, px)
    }

    @Test
    fun `the held rail of the real wall bars is found, tilted, not level`() {
        val line = RailFinder.find(wallBars(), wristX = 155f, wristY = 44f, halfWidth = 70, above = 30)
        assertNotNull(line)
        assertEquals(7.4f, line!!.degrees, 1.5f)
        assertEquals(40f, line.yAt(155f), 2.5f)
    }

    @Test
    fun `a hand lower on the same wall holds the nearest rail above it, not the best one`() {
        // The wrist is under the second rail: the first is above it too, and is the one that
        // scored best in the learned stack, but it is not the one this hand can be holding.
        val line = RailFinder.find(wallBars(), wristX = 155f, wristY = 62f, halfWidth = 70, above = 30)
        assertNotNull(line)
        assertEquals(59f, line!!.yAt(155f), 2.5f)
    }

    @Test
    fun `an invented rail is found at its tilt and its height`() {
        val luma = synthetic(ys = listOf(60f, 80f), degrees = -5f)
        val line = RailFinder.find(luma, wristX = 150f, wristY = 63f, halfWidth = 70, above = 30)
        assertNotNull(line)
        assertEquals(-5f, line!!.degrees, 1.5f)
        assertEquals(60f, line.yAt(150f), 2f)
    }

    @Test
    fun `an arm across the rail does not move it`() {
        val luma = synthetic(ys = listOf(60f), degrees = 8f)
        // An arm: a bright-as-the-rail vertical band 16 px wide, straight through the line.
        for (y in 0 until luma.height) for (x in 140..156) luma.pixels[y * luma.width + x] = 200.toByte()
        val line = RailFinder.find(luma, wristX = 148f, wristY = 62f, halfWidth = 70, above = 30)
        assertNotNull(line)
        assertEquals(8f, line!!.degrees, 1.5f)
        assertEquals(60f, line.yAt(150f), 2.5f)
    }

    @Test
    fun `a bare wall has no rail to find`() {
        val luma = synthetic(ys = emptyList(), degrees = 0f)
        assertNull(RailFinder.find(luma, wristX = 150f, wristY = 70f, halfWidth = 70, above = 30))
    }

    @Test
    fun `a hand at the edge of the picture neither crashes nor invents a rail`() {
        val luma = synthetic(ys = emptyList(), degrees = 0f)
        assertNull(RailFinder.find(luma, wristX = 4f, wristY = 3f, halfWidth = 70, above = 30))
        assertNull(RailFinder.find(luma, wristX = 295f, wristY = 138f, halfWidth = 70, above = 30))
    }
}
