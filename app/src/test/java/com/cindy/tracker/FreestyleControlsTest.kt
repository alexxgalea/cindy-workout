package com.cindy.tracker

import com.cindy.tracker.Availability.ABSENT
import com.cindy.tracker.Availability.ENABLED
import com.cindy.tracker.CameraControl.END
import com.cindy.tracker.CameraControl.SKIP
import com.cindy.tracker.CameraControl.SHUTTER
import com.cindy.tracker.WorkoutState.FINISHED
import com.cindy.tracker.WorkoutState.IDLE
import com.cindy.tracker.WorkoutState.PAUSED
import com.cindy.tracker.WorkoutState.RUNNING
import com.cindy.tracker.WorkoutState.SETUP
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins Freestyle's control row (#189): STOP stands in END's place, SKIP's place stays empty,
 * the names at the phone are STOP and RESUME, and START goes straight to running. Cindy's
 * panels are pinned by [CameraControlsTest] and stay as they were.
 */
class FreestyleControlsTest {

    private val freestyle = Workout(
        id = "freestyle",
        name = "Freestyle",
        structure = Structure.FREE,
        movements = Exercise.entries.map { Prescription(it, null) },
        timeCapMs = null,
        scoring = Scoring.TOTALS,
        description = "Pull-ups, push-ups and squats, in any order."
    )

    private fun panel(state: WorkoutState, filming: Boolean = false) =
        CameraControls.of(state, filming, freestyle)

    @Test
    fun `STOP stands in END's place, there while a workout is live`() {
        for (state in WorkoutState.entries) {
            val live = state == RUNNING || state == PAUSED
            assertEquals("$state", if (live) ENABLED else ABSENT, panel(state)[END].availability)
        }
        assertEquals("Stop the workout", panel(RUNNING)[END].name)
    }

    @Test
    fun `SKIP is absent in every state, with and without a film`() {
        for (state in WorkoutState.entries) {
            for (filming in listOf(false, true)) {
                assertEquals("$state", ABSENT, panel(state, filming)[SKIP].availability)
            }
        }
    }

    @Test
    fun `the shutter is as in Cindy, and every other control is unchanged`() {
        for (state in WorkoutState.entries) {
            val cindy = CameraControls.of(state, false)
            for (control in CameraControl.entries - setOf(END, SKIP)) {
                assertEquals("$control in $state", cindy[control], panel(state)[control])
            }
        }
        assertEquals(ENABLED, panel(IDLE)[SHUTTER].availability)
    }

    @Test
    fun `START goes straight to running for Freestyle and to the setup check for Cindy`() {
        assertEquals(RUNNING, CameraControls.stateAfterStart(freestyle))
        assertEquals(SETUP, CameraControls.stateAfterStart(Workouts.CINDY))
        assertEquals(SETUP, CameraControls.stateAfterStart(null))
    }

    @Test
    fun `at the phone a pause names STOP and RESUME, and no SKIP`() {
        val names = ControlNames.of(PAUSED, panel(PAUSED), freestyle)
        assertEquals("STOP", names.end)
        assertEquals("RESUME", names.shutter)
        assertNull(names.skip)
    }

    @Test
    fun `the clock running names nothing, idle and finished carry the idle line`() {
        val running = ControlNames.of(RUNNING, panel(RUNNING), freestyle)
        assertNull(running.end)
        assertNull(running.shutter)
        assertNull(running.skip)
        for (state in listOf(IDLE, FINISHED)) {
            val line = ControlNames.of(state, panel(state), freestyle).idleLine
            assertNotNull(line)
            assertEquals("Freestyle · Press the shutter to start", line)
        }
    }

    @Test
    fun `the idle line still leads with the chosen workout's name`() {
        assertEquals("Freestyle · Press the shutter to start", CameraControls.idleLine(freestyle))
        assertEquals("Cindy · Press the shutter to start the setup check", CameraControls.idleLine(Workouts.CINDY))
    }

    @Test
    fun `the rep editors are dimmed until a movement is recognised, and only then`() {
        val running = panel(RUNNING)
        assertEquals(ENABLED, running[CameraControl.PLUS].availability)
        val waiting = running.withEditors(recognised = false)
        for (editor in listOf(CameraControl.MINUS, CameraControl.PLUS)) {
            assertEquals(Availability.DIMMED, waiting[editor].availability)
            assertEquals(running[editor].name, waiting[editor].name)
        }
        assertEquals(ENABLED, waiting[SHUTTER].availability)
        assertEquals(running, running.withEditors(recognised = true))
    }
}
