package com.cindy.tracker

import com.cindy.tracker.Availability.ABSENT
import com.cindy.tracker.Availability.DIMMED
import com.cindy.tracker.Availability.ENABLED
import com.cindy.tracker.CameraControl.END
import com.cindy.tracker.CameraControl.MINUS
import com.cindy.tracker.CameraControl.PLUS
import com.cindy.tracker.CameraControl.SHUTTER
import com.cindy.tracker.CameraControl.SKIP
import com.cindy.tracker.CameraControl.SWITCH_CAMERA
import com.cindy.tracker.WorkoutState.FINISHED
import com.cindy.tracker.WorkoutState.IDLE
import com.cindy.tracker.WorkoutState.PAUSED
import com.cindy.tracker.WorkoutState.RUNNING
import com.cindy.tracker.WorkoutState.SETUP
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins what the camera screen's controls do today, state by state. These are the rules the
 * activity used to hold in `renderControls`; the tickets that change them change the table
 * below, and nothing else.
 */
class CameraControlsTest {

    /** One row per state: what each control is, in the order of [CameraControl]. */
    private val today: Map<WorkoutState, Map<CameraControl, Availability>> = mapOf(
        //          switch    END     shutter  minus    plus     skip
        IDLE to row(ENABLED, ABSENT, ENABLED, DIMMED, DIMMED, DIMMED),
        SETUP to row(ENABLED, ABSENT, DIMMED, DIMMED, DIMMED, ENABLED),
        RUNNING to row(ABSENT, ENABLED, ENABLED, ENABLED, ENABLED, ENABLED),
        PAUSED to row(ABSENT, ENABLED, ENABLED, DIMMED, DIMMED, ENABLED),
        FINISHED to row(ENABLED, ABSENT, ENABLED, DIMMED, DIMMED, DIMMED)
    )

    private fun row(
        switch: Availability,
        end: Availability,
        shutter: Availability,
        minus: Availability,
        plus: Availability,
        skip: Availability
    ) = mapOf(
        SWITCH_CAMERA to switch, END to end, SHUTTER to shutter,
        MINUS to minus, PLUS to plus, SKIP to skip
    )

    @Test
    fun `every state, with and without a film, answers as the camera screen does today`() {
        for ((state, expected) in today) {
            for (filming in listOf(false, true)) {
                val controls = CameraControls.of(state, filming)
                for (control in CameraControl.entries) {
                    assertEquals(
                        "$control in $state, filming=$filming",
                        expected.getValue(control),
                        controls[control].availability
                    )
                }
            }
        }
    }

    @Test
    fun `the table covers every state`() {
        assertEquals(WorkoutState.entries.toSet(), today.keys)
    }

    @Test
    fun `a film changes nothing about the controls today`() {
        for (state in WorkoutState.entries) {
            assertEquals(CameraControls.of(state, false), CameraControls.of(state, true))
        }
    }

    @Test
    fun `the camera switch is there exactly while no workout is live`() {
        for (state in WorkoutState.entries) {
            val live = state == RUNNING || state == PAUSED
            assertEquals("$state", !live, CameraControls.of(state, false)[SWITCH_CAMERA].present)
        }
    }

    @Test
    fun `END takes the left slot once a workout is live, and never shares it with the switch`() {
        for (state in WorkoutState.entries) {
            val controls = CameraControls.of(state, false)
            assertTrue(
                "$state: one of the two holds the slot",
                controls[END].present != controls[SWITCH_CAMERA].present
            )
            val live = state == RUNNING || state == PAUSED
            assertEquals("$state", live, controls[END].present)
        }
    }

    @Test
    fun `the counters edit a count, and the count only moves while the clock runs`() {
        for (state in WorkoutState.entries) {
            val controls = CameraControls.of(state, false)
            assertEquals("$state", state == RUNNING, controls[MINUS].enabled)
            assertEquals("$state", state == RUNNING, controls[PLUS].enabled)
            assertTrue("$state: dimmed, never hidden", controls[MINUS].present && controls[PLUS].present)
        }
    }

    @Test
    fun `the shutter is inert only during the setup check`() {
        for (state in WorkoutState.entries) {
            assertEquals("$state", state != SETUP, CameraControls.of(state, false)[SHUTTER].enabled)
        }
    }

    @Test
    fun `SKIP has a movement to leave during the check and during the workout`() {
        for (state in WorkoutState.entries) {
            val expected = state == SETUP || state == RUNNING || state == PAUSED
            assertEquals("$state", expected, CameraControls.of(state, false)[SKIP].enabled)
        }
    }

    @Test
    fun `a control that is present is enabled or dimmed, and dimmed is not enabled`() {
        assertTrue(ENABLED.let { ControlState(it, "x").present && ControlState(it, "x").enabled })
        assertTrue(DIMMED.let { ControlState(it, "x").present && !ControlState(it, "x").enabled })
        assertFalse(ControlState(ABSENT, "x").present)
        assertFalse(ControlState(ABSENT, "x").enabled)
    }

    @Test
    fun `the spoken names are the ones TalkBack hears today`() {
        val names = mapOf(
            SWITCH_CAMERA to "Switch camera",
            END to "End the workout",
            MINUS to "Take back a rep",
            PLUS to "Add a rep"
        )
        for (state in WorkoutState.entries) {
            val controls = CameraControls.of(state, false)
            for ((control, name) in names) assertEquals("$control in $state", name, controls[control].name)
        }
    }

    @Test
    fun `the shutter is named for the job it does in each state`() {
        assertEquals("Start the workout", CameraControls.of(IDLE, false)[SHUTTER].name)
        assertEquals(
            "Start — available once the setup check finishes",
            CameraControls.of(SETUP, false)[SHUTTER].name
        )
        assertEquals("Pause", CameraControls.of(RUNNING, false)[SHUTTER].name)
        assertEquals("Resume", CameraControls.of(PAUSED, false)[SHUTTER].name)
        assertEquals("Start the workout", CameraControls.of(FINISHED, false)[SHUTTER].name)
    }

    @Test
    fun `SKIP is named for what it leaves`() {
        assertEquals("Skip the setup check", CameraControls.of(SETUP, false)[SKIP].name)
        for (state in listOf(IDLE, RUNNING, PAUSED, FINISHED)) {
            assertEquals("$state", "Skip to the next movement", CameraControls.of(state, false)[SKIP].name)
        }
    }

    @Test
    fun `closing the session page returns the camera screen to idle, whichever way it closes and whatever it was doing`() {
        // DONE, DISCARD and the back gesture all land on the camera screen the same way, so the
        // module has one answer for all three: the finished workout is not left for the athlete.
        for (state in WorkoutState.entries) {
            for (filming in listOf(false, true)) {
                assertEquals(
                    "$state, filming=$filming",
                    IDLE,
                    CameraControls.of(state, filming).afterSessionPage
                )
            }
        }
    }

    @Test
    fun `nothing the camera screen says or names offers AGAIN`() {
        for (state in WorkoutState.entries) {
            val controls = CameraControls.of(state, false)
            for (control in CameraControl.entries) {
                val name = controls[control].name
                assertFalse("$control in $state is called \"$name\"", name.contains("again", ignoreCase = true))
            }
        }
    }
}
