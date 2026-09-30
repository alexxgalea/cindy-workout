package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

class StravaPayloadTest {

    // ---- StravaExercises: the §2 mapping table -------------------------------------------

    @Test
    fun `every pull variant maps to the table's exercise type`() {
        val expected = mapOf(
            PullVariant.STRICT_PULL_UP to "PULL_UP_GENERIC",
            PullVariant.BAND_ASSISTED_PULL_UP to "PULL_UP_GENERIC",
            PullVariant.INVERTED_ROW to "INVERTED_ROW",
            PullVariant.FOOT_ASSISTED_PULL_UP to "PULL_UP_GENERIC",
            PullVariant.NEGATIVE_PULL_UP to "NEGATIVE_PULL_UP"
        )
        // Iterating entries, rather than listing the map above by hand, is what would catch a
        // variant someone added and forgot to expect here — the same protection the exhaustive
        // `when` in StravaExercises gives the production code.
        for (variant in PullVariant.entries) {
            val profile = CindyProfile(pull = variant)
            assertEquals(variant.name, expected.getValue(variant), StravaExercises.typeFor(Exercise.PULLUP, profile))
        }
    }

    @Test
    fun `every push variant maps to the table's exercise type`() {
        val expected = mapOf(
            PushVariant.STANDARD_PUSH_UP to "PUSH_UP_GENERIC",
            PushVariant.KNEE_PUSH_UP to "MODIFIED_PUSH_UP",
            PushVariant.INCLINE_PUSH_UP to "INCLINE_PUSH_UP"
        )
        for (variant in PushVariant.entries) {
            val profile = CindyProfile(push = variant)
            assertEquals(variant.name, expected.getValue(variant), StravaExercises.typeFor(Exercise.PUSHUP, profile))
        }
    }

    @Test
    fun `every squat variant maps to the table's exercise type`() {
        val expected = mapOf(
            SquatVariant.AIR_SQUAT to "AIR_SQUAT",
            SquatVariant.BOX_SQUAT to "SQUAT_GENERIC",
            SquatVariant.SUPPORTED_SQUAT to "SQUAT_GENERIC"
        )
        for (variant in SquatVariant.entries) {
            val profile = CindyProfile(squat = variant)
            assertEquals(variant.name, expected.getValue(variant), StravaExercises.typeFor(Exercise.SQUAT, profile))
        }
    }

    @Test
    fun `a null profile falls back to each movement's generic type`() {
        assertEquals("PULL_UP_GENERIC", StravaExercises.typeFor(Exercise.PULLUP, null))
        assertEquals("PUSH_UP_GENERIC", StravaExercises.typeFor(Exercise.PUSHUP, null))
        assertEquals("SQUAT_GENERIC", StravaExercises.typeFor(Exercise.SQUAT, null))
    }

    @Test
    fun `never claims equipment that was not used`() {
        // The exact regression the table exists to guard: a box squat is not a barbell squat.
        assertEquals(
            "SQUAT_GENERIC",
            StravaExercises.typeFor(Exercise.SQUAT, CindyProfile(squat = SquatVariant.BOX_SQUAT))
        )
    }
}
