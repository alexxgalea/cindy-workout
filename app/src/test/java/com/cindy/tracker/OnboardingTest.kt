package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTest {

    private fun show(seen: Boolean, history: Boolean, dismissed: Boolean) =
        Onboarding.shouldShowTutorial(seen, history, dismissed)

    @Test
    fun `a new install is shown around`() {
        assertTrue(show(seen = false, history = false, dismissed = false))
    }

    @Test
    fun `nobody is shown around twice`() {
        assertFalse(show(seen = true, history = false, dismissed = false))
    }

    @Test
    fun `someone with a session on record has used the app`() {
        assertFalse(show(seen = false, history = true, dismissed = false))
    }

    @Test
    fun `someone who dismissed the placement guide has used the app, records or not`() {
        assertFalse(show(seen = false, history = false, dismissed = true))
    }

    @Test
    fun `every combination, written out`() {
        // Shown only when none of the three says the app is not new to them.
        val expected = mapOf(
            Triple(false, false, false) to true,
            Triple(false, false, true) to false,
            Triple(false, true, false) to false,
            Triple(false, true, true) to false,
            Triple(true, false, false) to false,
            Triple(true, false, true) to false,
            Triple(true, true, false) to false,
            Triple(true, true, true) to false
        )
        for ((inputs, shown) in expected) {
            assertEquals(
                "seen=${inputs.first} history=${inputs.second} dismissed=${inputs.third}",
                shown,
                show(inputs.first, inputs.second, inputs.third)
            )
        }
    }

    @Test
    fun `the keys are the ones already on disk and never collide`() {
        // The placement key is an athlete's existing choice; renaming it would show the guide again.
        assertEquals("placement_guide_dismissed", Onboarding.KEY_PLACEMENT_SEEN)
        assertEquals(
            3,
            setOf(
                Onboarding.KEY_TUTORIAL_SEEN,
                Onboarding.KEY_HUD_TOUR_PENDING,
                Onboarding.KEY_PLACEMENT_SEEN
            ).size
        )
    }
}
