package com.cindy.tracker

import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
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

    // ---- StravaPayload.build ---------------------------------------------------------------

    private val finishedAt = Instant.parse("2026-01-01T00:11:00Z").toEpochMilli()

    // 11 real minutes (10 running, 1 paused), so start_time backdates to an even 00:00:00Z.
    private val attempt = Attempt(
        rounds = 5, reps = 3, atMillis = finishedAt,
        durationMs = 600_000L, pausedMs = 60_000L, countedReps = 153,
        profile = CindyProfile.STANDARD
    )
    private val standardSets = listOf(
        WorkoutSet(1, Exercise.PULLUP, 5),
        WorkoutSet(1, Exercise.PUSHUP, 10),
        WorkoutSet(1, Exercise.SQUAT, 15)
    )

    private fun build(
        sets: List<WorkoutSet> = standardSets,
        utcOffsetSeconds: Int = 0,
        kcal: Int? = null,
        heartRate: List<HrPoint>? = null
    ) = JSONObject(
        StravaPayload.build(attempt, sets, startMillisOf(attempt), utcOffsetSeconds, kcal, heartRate)
    )

    @Test
    fun `the required top-level fields are all present`() {
        val json = build(utcOffsetSeconds = 3600)
        assertEquals("1.0", json.getString("version"))
        assertEquals("2026-01-01T00:00:00Z", json.getString("start_time"))
        assertEquals(3600, json.getInt("utc_offset"))
        assertEquals(660, json.getInt("elapsed_time")) // 11 real minutes
        assertEquals(600, json.getInt("active_time")) // 10 running minutes
        assertEquals("Cindy Tracker", json.getJSONObject("creator").getString("name"))
    }

    @Test
    fun `sets carry exercise_type and repetitions, and never weight`() {
        val array = build().getJSONArray("sets")
        assertEquals(3, array.length())
        assertEquals("PULL_UP_GENERIC", array.getJSONObject(0).getString("exercise_type"))
        assertEquals(5, array.getJSONObject(0).getInt("repetitions"))
        assertFalse(array.getJSONObject(0).has("weight"))
    }

    @Test
    fun `a zero-rep set is omitted, since nothing was banked`() {
        val array = build(sets = standardSets + WorkoutSet(2, Exercise.PULLUP, 0)).getJSONArray("sets")
        assertEquals(3, array.length())
    }

    @Test
    fun `refuses to build a payload with nothing banked at all`() {
        try {
            build(sets = listOf(WorkoutSet(1, Exercise.PULLUP, 0)))
            fail("expected an IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // expected: the caller must never upload a zero-rep attempt.
        }
    }

    @Test
    fun `total_calories is omitted when kcal is null, present when given`() {
        assertFalse(build(kcal = null).has("total_calories"))
        assertEquals(420, build(kcal = 420).getInt("total_calories"))
    }

    @Test
    fun `streams is omitted when there is no heart rate at all`() {
        assertFalse(build(heartRate = null).has("streams"))
        assertFalse(build(heartRate = emptyList()).has("streams"))
    }

    @Test
    fun `streams holds equal-length time and heartrate arrays, with no active array`() {
        val heartRate = listOf(HrPoint(0, 90), HrPoint(30, 120), HrPoint(60, 140))
        val streams = build(heartRate = heartRate).getJSONObject("streams")
        val time = streams.getJSONArray("time")
        val hr = streams.getJSONArray("heartrate")
        assertEquals(3, time.length())
        assertEquals(time.length(), hr.length())
        assertEquals(listOf(0, 30, 60), (0 until time.length()).map { time.getInt(it) })
        assertEquals(listOf(90, 120, 140), (0 until hr.length()).map { hr.getInt(it) })
        // No samples exist while paused, so fabricating one would invent heart-rate data.
        assertFalse(streams.has("active"))
    }

    @Test
    fun `heart rate seconds are clamped between zero and elapsed_time`() {
        // elapsed_time is 660s (11 real minutes); -10 and 700 both fall outside it.
        val heartRate = listOf(HrPoint(-10, 80), HrPoint(300, 130), HrPoint(700, 150))
        val time = build(heartRate = heartRate).getJSONObject("streams").getJSONArray("time")
        assertEquals(listOf(0, 300, 660), (0 until time.length()).map { time.getInt(it) })
    }

    @Test
    fun `duplicate seconds created by clamping keep only the earliest-seen sample`() {
        // -5 and -1 both clamp to second 0; the first sample (80 bpm) must win, not 200.
        val heartRate = listOf(HrPoint(-5, 80), HrPoint(-1, 200), HrPoint(10, 100))
        val streams = build(heartRate = heartRate).getJSONObject("streams")
        val time = streams.getJSONArray("time")
        val hr = streams.getJSONArray("heartrate")
        assertEquals(2, time.length())
        assertEquals(0, time.getInt(0))
        assertEquals(80, hr.getInt(0))
        assertEquals(10, time.getInt(1))
        assertEquals(100, hr.getInt(1))
    }

    @Test
    fun `startMillisOf backdates the finish timestamp by the real time the attempt took`() {
        val a = Attempt(rounds = 1, reps = 0, atMillis = 1_000_000L, durationMs = 100_000L, pausedMs = 50_000L)
        assertEquals(850_000L, startMillisOf(a))
    }
}
