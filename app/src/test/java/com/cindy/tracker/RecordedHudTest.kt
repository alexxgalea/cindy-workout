package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What the burned-in recording shows, apart from what the screen shows.
 *
 * The setup check used to leave the film reading "ROUND 1" and "0 / 5" over the two calibration
 * pull-ups, because nothing fed the recorder anything else while it ran. These pin every stage's
 * strings, that the count follows [Setup.reps] and never the workout's own count, and the
 * banner's three-second window.
 */
class RecordedHudTest {

    private fun setup(stage: SetupStage, reps: Int = 0) =
        Setup(stage, missing = emptyList(), reps = reps, range = 20f, needed = 40f)

    @Test
    fun `framing shows a dash and the movement marked not scored`() {
        val hud = RecordedHud().forSetup(now = 0L, setup(SetupStage.FRAMING), label = "PULL-UPS")
        assertEquals("SETUP", hud.clock)
        assertEquals("CALIBRATION", hud.round)
        assertEquals("PULL-UPS · NOT SCORED", hud.label)
        assertEquals("– / 2", hud.count)
        assertNull(hud.banner)
    }

    @Test
    fun `framing shows the dash even once reps have been seen`() {
        // Framing can recur mid-check (an arm leaves the shot, say) without the two reps already
        // banked disappearing from the engine, but the count still has to read as unknown.
        val hud = RecordedHud().forSetup(now = 0L, setup(SetupStage.FRAMING, reps = 1), label = "PULL-UPS")
        assertEquals("– / 2", hud.count)
    }

    @Test
    fun `moving counts the calibration reps against the constant`() {
        val hud = RecordedHud().forSetup(now = 0L, setup(SetupStage.MOVING, reps = 1), label = "PULL-UPS")
        assertEquals("1 / 2", hud.count)
    }

    @Test
    fun `poor still shows the calibration count`() {
        val hud = RecordedHud().forSetup(now = 0L, setup(SetupStage.POOR, reps = 0), label = "PULL-UPS")
        assertEquals("0 / 2", hud.count)
        assertEquals("PULL-UPS · NOT SCORED", hud.label)
    }

    @Test
    fun `ready shows the finished calibration count`() {
        val hud = RecordedHud().forSetup(now = 0L, setup(SetupStage.READY, reps = 2), label = "PULL-UPS")
        assertEquals("2 / 2", hud.count)
    }

    @Test
    fun `a null setup reads the same as framing`() {
        // The one frame that can be rendered before the analysis thread has produced its first
        // setup reading.
        val hud = RecordedHud().forSetup(now = 0L, setup = null, label = "PULL-UPS")
        assertEquals("SETUP", hud.clock)
        assertEquals("CALIBRATION", hud.round)
        assertEquals("– / 2", hud.count)
    }

    @Test
    fun `the setup count follows Setup reps, never the workout count`() {
        val hud = RecordedHud()
        hud.workout(rounds = 6, reps = 4, target = 5)
        val text = hud.forSetup(now = 0L, setup(SetupStage.MOVING, reps = 1), label = "PULL-UPS")
        assertEquals("1 / 2", text.count)
        assertEquals("CALIBRATION", text.round)
    }

    @Test
    fun `workout strings are unchanged`() {
        val hud = RecordedHud()
        hud.workout(rounds = 3, reps = 3, target = 5)
        val text = hud.forWorkout(now = 0L, clock = "12:34", label = "PULL-UPS")
        assertEquals("12:34", text.clock)
        assertEquals("ROUND 4", text.round)
        assertEquals("PULL-UPS", text.label)
        assertEquals("3 / 5", text.count)
        assertNull(text.banner)
    }

    @Test
    fun `before any workout score arrives the film defaults the same way the screen does`() {
        val text = RecordedHud().forWorkout(now = 0L, clock = "20:00", label = "PULL-UPS")
        assertEquals("ROUND 1", text.round)
        assertEquals("0 / 5", text.count)
    }

    @Test
    fun `the calibrated banner is shown for three seconds and then gone`() {
        val hud = RecordedHud()
        hud.calibrated(now = 1_000L)
        assertEquals("CALIBRATED · 2 REPS", hud.forWorkout(1_000L, "20:00", "PULL-UPS").banner)
        assertEquals("CALIBRATED · 2 REPS", hud.forWorkout(1_000L + 2_999L, "20:00", "PULL-UPS").banner)
        assertNull(hud.forWorkout(1_000L + 3_000L, "20:00", "PULL-UPS").banner)
    }

    @Test
    fun `the skipped banner reads differently and times out the same way`() {
        val hud = RecordedHud()
        hud.skipped(now = 0L)
        assertEquals("CALIBRATION SKIPPED", hud.forWorkout(0L, "20:00", "PULL-UPS").banner)
        assertEquals("CALIBRATION SKIPPED", hud.forWorkout(2_999L, "20:00", "PULL-UPS").banner)
        assertNull(hud.forWorkout(3_000L, "20:00", "PULL-UPS").banner)
    }

    @Test
    fun `a banner showing when the setup HUD is asked for shows there too`() {
        val hud = RecordedHud()
        hud.calibrated(now = 0L)
        val text = hud.forSetup(now = 0L, setup(SetupStage.READY, reps = 2), label = "PULL-UPS")
        assertEquals("CALIBRATED · 2 REPS", text.banner)
    }

    @Test
    fun `no banner before one is triggered`() {
        assertNull(RecordedHud().forWorkout(0L, "20:00", "PULL-UPS").banner)
    }
}
