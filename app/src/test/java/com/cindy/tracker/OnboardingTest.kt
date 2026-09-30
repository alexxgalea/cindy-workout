package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTest {

    private fun show(
        seen: Boolean = false,
        history: Boolean = false,
        dismissed: Boolean = false,
        camera: Boolean = false
    ) = Onboarding.shouldShowTutorial(seen, history, dismissed, camera)

    @Test
    fun `a new install is shown around`() {
        assertTrue(show())
    }

    @Test
    fun `nobody is shown around twice`() {
        assertFalse(show(seen = true))
    }

    @Test
    fun `someone with a session on record has used the app`() {
        assertFalse(show(history = true))
    }

    @Test
    fun `someone who dismissed the placement guide has used the app, records or not`() {
        assertFalse(show(dismissed = true))
    }

    @Test
    fun `someone who already holds the camera permission has used the app`() {
        // A fresh install cannot: Android starts every one without it. An athlete who updated from
        // a version older than these pages has held it since the first time they opened the camera,
        // and may never have finished a session or met the placement guide.
        assertFalse(show(camera = true))
    }

    @Test
    fun `any one sign that the app is not new is enough, and every combination agrees`() {
        for (bits in 0 until 16) {
            val seen = bits and 1 != 0
            val history = bits and 2 != 0
            val dismissed = bits and 4 != 0
            val camera = bits and 8 != 0
            assertEquals(
                "seen=$seen history=$history dismissed=$dismissed camera=$camera",
                bits == 0,
                show(seen, history, dismissed, camera)
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
