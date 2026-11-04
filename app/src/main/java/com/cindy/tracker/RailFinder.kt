package com.cindy.tracker

import kotlin.math.atan
import kotlin.math.floor
import kotlin.math.tan

/** A grey picture: one byte per pixel, row after row. */
class Luma(val width: Int, val height: Int, val pixels: ByteArray) {
    init {
        require(pixels.size == width * height) { "$width x $height needs ${width * height} pixels" }
    }

    operator fun get(x: Int, y: Int): Int = pixels[y * width + x].toInt() and 0xFF
}

/**
 * A straight line in frame pixels, which is how a bar looks to a camera that is not level with it:
 * tilted, not horizontal. Defined by one point on it and a slope in pixels of y per pixel of x.
 */
data class RailLine(val slope: Float, val xRef: Float, val yRef: Float) {
    fun yAt(x: Float): Float = yRef + slope * (x - xRef)

    /** The tilt in degrees; positive runs down to the right on screen. */
    val degrees: Float get() = Math.toDegrees(atan(slope.toDouble())).toFloat()
}

/**
 * Finds the pull-up bar in the picture itself, from where a hand is.
 *
 * The pose gives the hands but not the bar they hold, and the bar learned from them has been a
 * guess: on the recorded wall bars it sat 30 px below the real one, a rail and a half off, and
 * level where the real one is tilted by seven degrees. This looks at the pixels near the hand
 * instead. It is for *drawing* the bar, never for deciding whether a rep counts; [BarZone] stays
 * the gate.
 *
 * A bar is a thin bright line that runs a long way in one direction, so the picture is first
 * reduced to its thin bright parts (a white top-hat, one pixel wide and [THIN] tall), and then
 * every straight line near the hand within [MAX_TILT] degrees is scored by the *median* of the
 * thin-bright response along it. The median, not the mean: an arm or a hand crossing a line cannot
 * carry its score, and a window edge that is bright over a short stretch cannot either.
 *
 * A wall of bars has several rails a few pixels apart, and the line of best score is not
 * necessarily the one being held. The tilt is taken from the best line and then the choice is made
 * by the hand, in two steps. A hand hangs from the rail and never below it, so only rails at or
 * above the wrist are candidates. But the pose puts the wrist where the hand ends, not where it
 * grips: on the recorded wall bars it read a hand's length *under* the tube (14 px, with the next
 * rail 5 px above it), so the *nearest* rail above the wrist was the wrong one. Candidates are
 * therefore every rail within [reach] above the wrist, and the one that looks most like a bar wins.
 */
object RailFinder {
    /** Tallest thing, in pixels, that still counts as thin: a bar is a few pixels, a wall is not. */
    const val THIN = 13

    /** Steepest tilt searched, in degrees either side of level. */
    const val MAX_TILT = 12f
    private const val TILT_STEP = 0.5f

    /** A line scoring under this, in grey levels, is wall, not bar. */
    const val MIN_SCORE = 8f

    /** A rail scoring under this share of the best line's score is a smudge, not a rail. */
    private const val CANDIDATE_SHARE = 0.5f

    /** Rails within this share of the strongest are a tie, and the highest of them is the bar. */
    private const val TIE_SHARE = 0.85f

    /** A wrist can read a few pixels below the rail it holds: the hand wraps the bar. */
    const val WRIST_SLACK = 4f

    private const val X_STEP = 3

    /**
     * The bar held by the hand at ([wristX], [wristY]), or null when the picture shows none.
     *
     * [halfWidth] is how far either side of the hand to look, [above] how far above it to look for
     * the tilt, and [reach] how far above the wrist the held bar can be: all in pixels of [luma], so
     * the caller scales them from the body (a torso is a good unit). A hand's length is [reach].
     */
    fun find(luma: Luma, wristX: Float, wristY: Float, halfWidth: Int, above: Int, reach: Int): RailLine? {
        val tiltDrift = (halfWidth * tan(Math.toRadians(MAX_TILT.toDouble()))).toInt() + 1
        val x0 = (wristX - halfWidth).toInt().coerceAtLeast(0)
        val x1 = (wristX + halfWidth).toInt().coerceAtMost(luma.width - 1)
        val y0 = (wristY - above - tiltDrift - THIN).toInt().coerceAtLeast(0)
        val y1 = (wristY + WRIST_SLACK + tiltDrift + THIN).toInt().coerceAtMost(luma.height - 1)
        if (x1 - x0 < 8 || y1 - y0 < THIN) return null

        val thin = thinBright(luma, x0, y0, x1, y1)

        val xs = (wristX.toInt() - halfWidth..wristX.toInt() + halfWidth step X_STEP)
            .filter { it in x0..x1 }
        if (xs.size < 8) return null
        val offsets = (-above..WRIST_SLACK.toInt()).toList()
        val samples = FloatArray(xs.size)

        fun score(slope: Float, y: Float): Float {
            for ((i, x) in xs.withIndex()) {
                samples[i] = thin.at(x.toFloat(), y + slope * (x - wristX))
            }
            samples.sort()
            return samples[samples.size / 2]
        }

        var bestScore = -1f
        var bestSlope = 0f
        var tilt = -MAX_TILT
        while (tilt <= MAX_TILT) {
            val slope = tan(Math.toRadians(tilt.toDouble())).toFloat()
            for (dy in offsets) {
                val s = score(slope, wristY + dy)
                if (s > bestScore) {
                    bestScore = s
                    bestSlope = slope
                }
            }
            tilt += TILT_STEP
        }
        if (bestScore < MIN_SCORE) return null

        val scores = FloatArray(offsets.size) { score(bestSlope, wristY + offsets[it]) }
        // Candidates: real peaks, within a hand's length above the wrist (and a little below it).
        val peaks = scores.indices.filter { i ->
            val lo = (i - 2).coerceAtLeast(0)
            val hi = (i + 2).coerceAtMost(scores.size - 1)
            offsets[i] >= -reach && scores[i] >= bestScore * CANDIDATE_SHARE &&
                (lo..hi).none { scores[it] > scores[i] }
        }
        if (peaks.isEmpty()) return null
        val top = peaks.maxOf { scores[it] }
        // The strongest wins; rails that look about as strong are decided by being the highest,
        // since a hand reaches up to the bar.
        val chosen = peaks.filter { scores[it] >= top * TIE_SHARE }.minByOrNull { offsets[it] }!!
        return RailLine(bestSlope, wristX, wristY + offsets[chosen])
    }

    /** The thin bright parts of [luma] in a window: the picture minus its vertical opening. */
    private class Thin(val x0: Int, val y0: Int, val w: Int, val h: Int, val v: FloatArray) {
        fun at(x: Float, y: Float): Float {
            val fx = x - x0
            val fy = y - y0
            val ix = floor(fx).toInt().coerceIn(0, w - 2)
            val iy = floor(fy).toInt().coerceIn(0, h - 2)
            val ax = (fx - ix).coerceIn(0f, 1f)
            val ay = (fy - iy).coerceIn(0f, 1f)
            val top = v[iy * w + ix] * (1 - ax) + v[iy * w + ix + 1] * ax
            val bottom = v[(iy + 1) * w + ix] * (1 - ax) + v[(iy + 1) * w + ix + 1] * ax
            return top * (1 - ay) + bottom * ay
        }
    }

    private fun thinBright(luma: Luma, x0: Int, y0: Int, x1: Int, y1: Int): Thin {
        val w = x1 - x0 + 1
        val h = y1 - y0 + 1
        val r = THIN / 2
        val eroded = IntArray(w * h)
        val opened = IntArray(w * h)
        for (x in 0 until w) {
            for (y in 0 until h) {
                var m = 255
                for (k in -r..r) m = minOf(m, luma[x0 + x, (y0 + y + k).coerceIn(0, luma.height - 1)])
                eroded[y * w + x] = m
            }
        }
        for (x in 0 until w) {
            for (y in 0 until h) {
                var m = 0
                for (k in -r..r) m = maxOf(m, eroded[(y + k).coerceIn(0, h - 1) * w + x])
                opened[y * w + x] = m
            }
        }
        val raw = FloatArray(w * h) { (luma[x0 + it % w, y0 + it / w] - opened[it]).toFloat() }
        // A light 1-2-1 blur each way, so a rail a pixel off the line still scores.
        val tmp = FloatArray(w * h)
        val out = FloatArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            tmp[y * w + x] = (raw[y * w + (x - 1).coerceAtLeast(0)] + 2 * raw[y * w + x] +
                raw[y * w + (x + 1).coerceAtMost(w - 1)]) / 4f
        }
        for (y in 0 until h) for (x in 0 until w) {
            out[y * w + x] = (tmp[(y - 1).coerceAtLeast(0) * w + x] + 2 * tmp[y * w + x] +
                tmp[(y + 1).coerceAtMost(h - 1) * w + x]) / 4f
        }
        return Thin(x0, y0, w, h, out)
    }

    /** The slope, in pixels of y per pixel of x, of a tilt in degrees. */
    fun slopeOf(degrees: Float): Float = tan(Math.toRadians(degrees.toDouble())).toFloat()
}
