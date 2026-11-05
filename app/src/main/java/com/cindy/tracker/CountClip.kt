package com.cindy.tracker

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/**
 * A spoken count kept from the engine's own synthesis: mono 16-bit samples at [sampleRate].
 *
 * The phone's engine is slow to be heard. The P40's leaves 200–330 ms of silence at the start of
 * every word it synthesizes, after Android has already reported it started. A count captured once
 * and trimmed is heard ~300 ms sooner than one synthesized when the rep is scored.
 */
class CountClip(val sampleRate: Int, val samples: ShortArray) {

    val durationMs: Long get() = samples.size * 1000L / sampleRate

    /**
     * This clip without the silence before the first sound and after the last, keeping
     * [keepMs] either side so the word's edges are not clipped.
     */
    fun trimmed(loud: Int = LOUD, keepMs: Int = KEEP_MS): CountClip {
        val first = samples.indexOfFirst { abs(it.toInt()) > loud }
        if (first < 0) return this
        val last = samples.indexOfLast { abs(it.toInt()) > loud }
        val keep = sampleRate * keepMs / 1000
        val from = (first - keep).coerceAtLeast(0)
        val to = (last + 1 + keep).coerceAtMost(samples.size)
        return CountClip(sampleRate, samples.copyOfRange(from, to))
    }

    companion object {
        /** A sample louder than this is speech. Engines pad with zeros or a faint hiss below it. */
        const val LOUD = 500
        const val KEEP_MS = 15

        /** A clip of little-endian 16-bit mono [pcm] at [sampleRate]. */
        fun fromPcm16(sampleRate: Int, pcm: ByteArray): CountClip {
            val b = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
            return CountClip(sampleRate, ShortArray(pcm.size / 2) { b.getShort(it * 2) })
        }
    }
}
