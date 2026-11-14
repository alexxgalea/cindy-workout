package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the camera screen writes under its controls, state by state (#167). Every expectation is
 * the ticket's table, not read back from the code: idle has no names and an idle line, setup
 * names SKIP, a pause names END, RESUME and SKIP, and the clock running names nothing.
 */
class ControlNamesTest {

    private fun names(state: WorkoutState) = ControlNames.of(state, CameraControls.of(state, filming = false))

    @Test
    fun `idle names no control and has the idle line under the shutter`() {
        val idle = names(WorkoutState.IDLE)
        assertNull(idle.end)
        assertNull(idle.shutter)
        assertNull(idle.skip)
        assertEquals("Press the shutter to start the setup check", idle.idleLine)
    }

    @Test
    fun `setup names SKIP alone, because the shutter is dimmed and END is absent`() {
        val setup = names(WorkoutState.SETUP)
        assertNull(setup.end)
        assertNull(setup.shutter)
        assertEquals("SKIP", setup.skip)
        assertNull(setup.idleLine)
    }

    @Test
    fun `a pause names END, RESUME and SKIP`() {
        val paused = names(WorkoutState.PAUSED)
        assertEquals("END", paused.end)
        assertEquals("RESUME", paused.shutter)
        assertEquals("SKIP", paused.skip)
        assertNull(paused.idleLine)
    }

    @Test
    fun `while the clock runs nothing is named, the athlete is at the bar`() {
        val running = names(WorkoutState.RUNNING)
        assertNull(running.end)
        assertNull(running.shutter)
        assertNull(running.skip)
        assertNull(running.idleLine)
    }

    @Test
    fun `a finished workout is drawn as idle`() {
        assertEquals(names(WorkoutState.IDLE), names(WorkoutState.FINISHED))
    }

    @Test
    fun `no dimmed control is ever named`() {
        for (state in WorkoutState.values()) {
            val panel = CameraControls.of(state, filming = false)
            val names = ControlNames.of(state, panel)
            if (!panel[CameraControl.END].enabled) assertNull("$state names END", names.end)
            if (!panel[CameraControl.SHUTTER].enabled) assertNull("$state names the shutter", names.shutter)
            if (!panel[CameraControl.SKIP].enabled) assertNull("$state names SKIP", names.skip)
        }
    }

    @Test
    fun `the coaching pill is shown in setup and paused, hidden in idle and finished`() {
        assertTrue(ControlNames.pillShown(WorkoutState.SETUP, statusBlank = false))
        assertTrue(ControlNames.pillShown(WorkoutState.PAUSED, statusBlank = false))
        assertTrue(ControlNames.pillShown(WorkoutState.RUNNING, statusBlank = false))
        assertFalse(ControlNames.pillShown(WorkoutState.IDLE, statusBlank = true))
        assertFalse(ControlNames.pillShown(WorkoutState.FINISHED, statusBlank = true))
    }

    @Test
    fun `a finished workout shows the coaching pill exactly when idle would`() {
        for (blank in listOf(true, false)) {
            assertEquals("statusBlank = $blank",
                ControlNames.pillShown(WorkoutState.IDLE, blank), ControlNames.pillShown(WorkoutState.FINISHED, blank))
        }
    }

    @Test
    fun `an error written while idle still gets the pill, because nothing else would say it`() {
        assertTrue(ControlNames.pillShown(WorkoutState.IDLE, statusBlank = false))
    }
}
