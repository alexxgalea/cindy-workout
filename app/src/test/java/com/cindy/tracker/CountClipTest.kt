package com.cindy.tracker

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class CountClipTest {

    @Test
    fun `little-endian pcm is read as samples`() {
        val clip = CountClip.fromPcm16(16_000, byteArrayOf(0x01, 0x00, 0xff.toByte(), 0xff.toByte(), 0x00, 0x10, 0x7))
        assertEquals(16_000, clip.sampleRate)
        assertArrayEquals(shortArrayOf(1, -1, 0x1000), clip.samples)
    }

    @Test
    fun `trimming drops the silence either side and keeps a margin`() {
        // 1 kHz: 300 ms of silence, 100 ms of speech, 200 ms of silence.
        val samples = ShortArray(600) { if (it in 300 until 400) 3000 else 10 }
        val clip = CountClip(1_000, samples).trimmed(keepMs = 15)
        assertEquals(130, clip.samples.size)
        assertEquals(10.toShort(), clip.samples.first())
        assertEquals(3000.toShort(), clip.samples[15])
        assertEquals(130L, clip.durationMs)
    }

    @Test
    fun `a clip with no speech in it is left alone`() {
        val clip = CountClip(1_000, ShortArray(50) { 3 })
        assertEquals(50, clip.trimmed().samples.size)
    }

    @Test
    fun `the margin never reaches past the clip`() {
        val clip = CountClip(1_000, ShortArray(20) { 3000 }).trimmed(keepMs = 15)
        assertEquals(20, clip.samples.size)
    }
}
