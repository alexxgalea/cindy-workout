package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The monitor's job is to notice that the score has stopped being trustworthy *before* the athlete
 * does, and — just as importantly — to stay quiet on footage that is merely difficult.
 *
 * The numbers these tests use are the ones measured by darkening real clips until they stopped
 * counting. A pull-up clip whose ground truth is five reps was 89% legible while scoring 5/5 and
 * 49% legible by the time it scored 3; a knee push-up clip sat at 31% legible the whole way
 * through and scored 12/12. Those two facts together are why the reading is a fraction of the
 * session's own baseline and never an absolute percentage.
 */
class TrackingHealthTest {

    private val monitor = TrackingHealthMonitor()
    private var clock = 0L

    /**
     * Feeds [ms] of frames at 30fps, of which [legible] is the share the camera could read.
     *
     * The legible frames are spread through the run rather than grouped, because a window that
     * happened to be filled with one or the other would test the arithmetic and not the rule.
     */
    private fun run(
        ms: Long,
        legible: Float,
        exercise: Exercise = Exercise.PULLUP,
        softGain: Float = 1f
    ) {
        val until = clock + ms
        var index = 0
        while (clock < until) {
            // Deterministic interleave: every frame whose position crosses the next 1/legible
            // boundary is a legible one.
            val readable = legible > 0f && (index * legible).toInt() < ((index + 1) * legible).toInt()
            monitor.update(exercise, readable, softGain, clock)
            clock += 33L
            index++
        }
    }

    @Test
    fun `a session the camera can read stays good and says nothing`() {
        run(10_000, legible = 1f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }

    @Test
    fun `footage that is merely difficult does not raise an alarm`() {
        // The knee push-up clip: only a third of frames fully legible, start to finish, and it
        // scores 12 of 12. An absolute threshold anywhere near half would condemn it.
        run(20_000, legible = 0.31f, exercise = Exercise.PUSHUP)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }

    @Test
    fun `legibility falling away from the session's own baseline warns before reps are lost`() {
        run(10_000, legible = 0.90f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        // 62% of a 0.90 baseline — past the warning line, short of the losing one. The clip was
        // still scoring every rep here, which is the moment a warning is worth giving.
        run(8_000, legible = 0.56f)
        assertEquals(TrackingHealth.WEAK, monitor.health)
        assertEquals("Losing you — more light helps", monitor.advice)
    }

    @Test
    fun `a collapse past half the baseline reports reps are being missed`() {
        run(10_000, legible = 0.90f)
        run(8_000, legible = 0.20f)
        assertEquals(TrackingHealth.LOST, monitor.health)
    }

    @Test
    fun `a brief dropout inside the dwell never reaches the athlete`() {
        run(10_000, legible = 1f)
        // Two seconds of nothing — a pull-up hiding its own wrists, or a walk past the camera.
        run(2_000, legible = 0f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }

    @Test
    fun `darkness is only claimed when the detector measured a dark picture`() {
        run(10_000, legible = 0.90f)
        run(8_000, legible = 0.10f, softGain = 6f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        assertEquals("Too dark to count — tap +1", monitor.advice)
    }

    @Test
    fun `an empty but well-lit frame is not blamed on the light`() {
        run(10_000, legible = 0.90f)
        // Same collapse, but the crop needed no brightening — so the app cannot claim darkness,
        // and says the one thing it does know.
        run(8_000, legible = 0.10f, softGain = 1f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        assertEquals("Can't see you — tap +1", monitor.advice)
    }

    @Test
    fun `recovering clears the advice without making the athlete wait`() {
        run(10_000, legible = 0.90f)
        run(8_000, legible = 0.10f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        // A light going on should read as having worked, so recovery is not held for the dwell.
        run(5_000, legible = 0.90f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }

    @Test
    fun `each movement is judged against its own baseline`() {
        // Pull-ups need both wrists overhead and are the first thing a fading light takes; squats
        // need ankles and survive far longer. A squat held to the pull-up's baseline would look
        // healthy when it was not, and vice versa.
        run(10_000, legible = 0.90f, exercise = Exercise.PULLUP)
        run(10_000, legible = 0.40f, exercise = Exercise.SQUAT)
        // 0.40 is under half the pull-up baseline, but it is the only squat reading there is, so
        // it establishes the squat baseline rather than condemning it.
        assertEquals(TrackingHealth.GOOD, monitor.health)
    }

    @Test
    fun `time spent unable to read the athlete is accumulated`() {
        run(10_000, legible = 0.90f)
        assertEquals(0L, monitor.lostMs)
        run(12_000, legible = 0.10f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        // The dwell and the window are not counted as lost time — only what followed them.
        assertTrue("expected several seconds of lost time, got ${monitor.lostMs}", monitor.lostMs > 3_000L)
        assertTrue(monitor.lostMs < 12_000L)
    }

    @Test
    fun `a moved camera forgets the baseline but not the damage`() {
        run(10_000, legible = 0.90f)
        run(12_000, legible = 0.10f)
        val suffered = monitor.lostMs
        assertTrue(suffered > 0L)
        monitor.reframe()
        // The new framing gets to establish its own baseline from scratch...
        run(10_000, legible = 0.45f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        // ...but the reps already missed were still missed.
        assertTrue(monitor.lostMs >= suffered)
    }

    @Test
    fun `nothing is reported before the window has filled`() {
        run(2_000, legible = 0f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }

    @Test
    fun `reset returns the monitor to a fresh session`() {
        run(10_000, legible = 0.90f)
        run(12_000, legible = 0.10f)
        assertNotNull(monitor.advice)
        monitor.reset()
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
        assertEquals(0L, monitor.lostMs)
        assertEquals(0L, monitor.weakMs)
    }

    @Test
    fun `a session that is unreadable from the first frame is not called healthy`() {
        // The case a purely relative reading cannot see: there is no good baseline to fall away
        // from, because nothing ever worked. Measured on a clip made bright but noisy — the
        // regime brightening cannot rescue — where not one frame in the whole clip was legible.
        run(12_000, legible = 0f, softGain = 2.4f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        assertEquals("Too dark to count — tap +1", monitor.advice)
    }

    @Test
    fun `a session that starts badly still recovers when the light comes on`() {
        run(12_000, legible = 0f)
        assertEquals(TrackingHealth.LOST, monitor.health)
        run(8_000, legible = 0.8f)
        assertEquals(TrackingHealth.GOOD, monitor.health)
        assertNull(monitor.advice)
    }
}
