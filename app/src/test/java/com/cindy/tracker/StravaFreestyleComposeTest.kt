package com.cindy.tracker

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StravaFreestyleComposeTest {

    private val a = Attempt(
        rounds = 0, reps = 0, atMillis = 700_000L, durationMs = 600_000L, countedReps = 15,
        workoutId = Workouts.FREESTYLE_ID, profile = CindyProfile.STANDARD,
        freestyleSets = listOf(
            FreestyleSet(Exercise.PUSHUP, 10, 1_000, 20_000),
            FreestyleSet(Exercise.PULLUP, 5, 30_000, 40_000)
        )
    )

    @Test
    fun `a Freestyle upload is named, listed by set and carries heart rate like a Cindy`() {
        val start = startMillisOf(a)
        val trace = HeartRateTrace(
            start, listOf(HeartRateSample(1_000L, 120), HeartRateSample(60_000L, 150)), emptyList()
        )
        val sets = StravaSets.from(a)!!
        val c = StravaComposer.compose(a, sets, start, 0, trace, Body(70.0, 30, Sex.MALE))

        assertEquals("Freestyle", c.name)
        assertTrue(c.description.contains("Sets: Push-ups 10, Pull-ups 5"))
        assertTrue(c.description.contains("heart rate"))
        val json = JSONObject(c.payload)
        assertEquals(2, json.getJSONArray("sets").length())
        assertEquals("PUSH_UP_GENERIC", json.getJSONArray("sets").getJSONObject(0).getString("exercise_type"))
        assertEquals(10, json.getJSONArray("sets").getJSONObject(0).getInt("repetitions"))
        assertTrue(json.getJSONObject("streams").getJSONArray("heartrate").length() > 0)
    }
}
