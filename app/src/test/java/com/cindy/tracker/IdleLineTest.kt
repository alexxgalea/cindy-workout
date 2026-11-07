package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IdleLineTest {

    @Test
    fun `the idle line points at the shutter and does not read as a line to tap`() {
        val line = CameraControls.IDLE_LINE
        assertTrue(line, line.contains("shutter"))
        assertTrue(line, line.contains("setup check"))
        assertFalse(line, line.contains("tap", ignoreCase = true))
    }

    @Test
    fun `the shutter it points at is still named as the way to start`() {
        assertEquals(
            "Start the workout",
            CameraControls.of(WorkoutState.IDLE, filming = false)[CameraControl.SHUTTER].name
        )
    }
}
