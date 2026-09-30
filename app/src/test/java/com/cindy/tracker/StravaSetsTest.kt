package com.cindy.tracker

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StravaSetsTest {

    private fun split(movement: Exercise, reps: Int) = SetSplit(movement, ms = 1_000L, reps = reps, manualReps = 0)

    private fun attempt(
        setSplits: List<SetSplit>,
        countedReps: Int?,
        profile: CindyProfile? = CindyProfile.STANDARD
    ) = Attempt(
        rounds = 0, reps = 0, atMillis = 0L, countedReps = countedReps,
        setSplits = setSplits, profile = profile
    )

    @Test
    fun `a clean two rounds plus a partial movement gives every set in order`() {
        val splits = listOf(
            split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15),
            split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15)
        )
        val a = attempt(splits, countedReps = 63) // two full rounds (60) + 3 pull-ups in progress

        assertEquals(
            listOf(
                WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 10), WorkoutSet(1, Exercise.SQUAT, 15),
                WorkoutSet(2, Exercise.PULLUP, 5), WorkoutSet(2, Exercise.PUSHUP, 10), WorkoutSet(2, Exercise.SQUAT, 15),
                WorkoutSet(3, Exercise.PULLUP, 3)
            ),
            StravaSets.from(a)
        )
    }

    @Test
    fun `a mid-round skip books what the split actually banked, not its target`() {
        val splits = listOf(split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 3)) // push-ups skipped at 3, not 10
        val a = attempt(splits, countedReps = 12) // 5 + 3 + 4 squats in progress

        assertEquals(
            listOf(
                WorkoutSet(1, Exercise.PULLUP, 5),
                WorkoutSet(1, Exercise.PUSHUP, 3),
                WorkoutSet(1, Exercise.SQUAT, 4)
            ),
            StravaSets.from(a)
        )
    }

    @Test
    fun `stopping right as a round completes adds no extra zero-rep set`() {
        val splits = listOf(split(Exercise.PULLUP, 5), split(Exercise.PUSHUP, 10), split(Exercise.SQUAT, 15))
        val a = attempt(splits, countedReps = 30) // nothing yet in round two

        assertEquals(
            listOf(WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 10), WorkoutSet(1, Exercise.SQUAT, 15)),
            StravaSets.from(a)
        )
    }

    @Test
    fun `no splits at all still gives the pull-ups in progress`() {
        val a = attempt(emptyList(), countedReps = 3)
        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 3)), StravaSets.from(a))
    }

    @Test
    fun `an inferred tally is never uploaded`() {
        val a = attempt(listOf(split(Exercise.PULLUP, 5)), countedReps = null)
        assertNull(StravaSets.from(a))
    }

    @Test
    fun `a split that breaks the engine's cycle is refused`() {
        // The very first split should be PULLUP, not PUSHUP.
        val brokenFirst = attempt(listOf(split(Exercise.PUSHUP, 10)), countedReps = 10)
        assertNull(StravaSets.from(brokenFirst))

        // The second split should be PUSHUP, not SQUAT.
        val brokenSecond = attempt(
            listOf(split(Exercise.PULLUP, 5), split(Exercise.SQUAT, 15)),
            countedReps = 20
        )
        assertNull(StravaSets.from(brokenSecond))
    }

    @Test
    fun `a remainder at or past the in-progress movement's target is refused`() {
        // Five is PULLUP's target: a movement that reaches it has already advanced and been
        // banked by SplitBook, so it cannot still be "in progress".
        val a = attempt(emptyList(), countedReps = 5)
        assertNull(StravaSets.from(a))
    }

    @Test
    fun `a negative remainder is refused`() {
        // The splits already total 5, but the attempt claims only 3 -- the record disagrees
        // with itself.
        val a = attempt(listOf(split(Exercise.PULLUP, 5)), countedReps = 3)
        assertNull(StravaSets.from(a))
    }

    @Test
    fun `an all-zero attempt has no positive set to upload`() {
        val a = attempt(emptyList(), countedReps = 0)
        assertNull(StravaSets.from(a))
    }

    @Test
    fun `the adaptive profile on the attempt reaches StravaPayload's mapping`() {
        val a = attempt(
            listOf(split(Exercise.PULLUP, 5)),
            countedReps = 13, // 5 pull-ups + 8 knee push-ups in progress
            profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        )
        val sets = StravaSets.from(a)
        assertEquals(listOf(WorkoutSet(1, Exercise.PULLUP, 5), WorkoutSet(1, Exercise.PUSHUP, 8)), sets)

        val json = JSONObject(StravaPayload.build(a, sets!!, startMillisOf(a), 0, null, null))
        val pushSet = json.getJSONArray("sets").getJSONObject(1)
        assertEquals("MODIFIED_PUSH_UP", pushSet.getString("exercise_type"))
    }
}
