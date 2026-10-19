package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The chosen workout as the profile keeps it: Cindy until chosen, and never an error. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProfileWorkoutTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `it is Cindy until another is chosen`() {
        assertEquals(Workouts.CINDY, Profile(context).workout)
    }

    @Test
    fun `a chosen workout is remembered, by its id`() {
        Profile(context).workout = Workouts.CINDY
        assertEquals(Workouts.CINDY, Profile(context).workout)
        assertEquals(
            "cindy",
            context.getSharedPreferences("cindy", Context.MODE_PRIVATE).getString("workout", null)
        )
    }

    /** A choice made in a newer build and restored from a backup, say. */
    @Test
    fun `a workout this build does not know reads back as Cindy`() {
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE)
            .edit().putString("workout", "murph").commit()
        assertEquals(Workouts.CINDY, Profile(context).workout)
    }
}
