package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the device video test may claim. A clip whose label needs the desktop batch's low-light
 * model or its tracking verdict must be reported as not run, and a clip without a capture rate
 * must still get a frame rate from its length.
 */
class DeviceRunPlanTest {

    @Test
    fun `capture rate wins when the clip has one`() {
        assertEquals(30f, DeviceRunPlan.framesPerSecond("30", 300, "20000")!!, 0.001f)
    }

    @Test
    fun `a downloaded clip gets its rate from frames over duration`() {
        // 532 frames in 17.7 s is the 30 fps clip the label was written against.
        assertEquals(30.056f, DeviceRunPlan.framesPerSecond(null, 532, "17700")!!, 0.01f)
    }

    @Test
    fun `no capture rate and no duration is no rate`() {
        assertNull(DeviceRunPlan.framesPerSecond(null, 532, null))
        assertNull(DeviceRunPlan.framesPerSecond(null, 532, "0"))
        assertNull(DeviceRunPlan.framesPerSecond(null, 532, "soon"))
    }

    @Test
    fun `an unusable capture rate falls back to the duration`() {
        assertEquals(25f, DeviceRunPlan.framesPerSecond("0", 250, "10000")!!, 0.001f)
    }

    @Test
    fun `a plain clip is run`() {
        assertNull(DeviceRunPlan.notRunReason("youtube_squats_two_rep_demo", hasLight = false, expectedTracking = null))
    }

    @Test
    fun `a clip with a light model is not run and says why`() {
        val reason = DeviceRunPlan.notRunReason("dim", hasLight = true, expectedTracking = null)
        assertEquals(
            "NOT RUN on device: low-light model and expected tracking are only applied by the desktop batch: dim",
            reason
        )
    }

    @Test
    fun `a clip that expects a tracking verdict is not run`() {
        assertTrue(DeviceRunPlan.notRunReason("lost", hasLight = false, expectedTracking = "LOST")!!.endsWith(": lost"))
    }

    @Test
    fun `a blank tracking label counts as none`() {
        assertNull(DeviceRunPlan.notRunReason("x", hasLight = false, expectedTracking = " "))
    }

    @Test
    fun `the summary lists every clip that was not run`() {
        val summary = DeviceRunPlan.notRunSummary(listOf("NOT RUN on device: a: one", "NOT RUN on device: b: two"))
        assertEquals(
            "2 scenario(s) NOT RUN on device, not counted as passes:\nNOT RUN on device: a: one\nNOT RUN on device: b: two",
            summary
        )
    }
}
