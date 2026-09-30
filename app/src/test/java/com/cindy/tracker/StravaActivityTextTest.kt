package com.cindy.tracker

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StravaActivityTextTest {

    // ---- name() -----------------------------------------------------------------------------

    @Test
    fun `a standard Cindy names itself with the score`() {
        val a = Attempt(rounds = 17, reps = 12, atMillis = 0L, profile = CindyProfile.STANDARD)
        assertEquals("Cindy — 17 + 12", StravaActivityText.name(a))
    }

    @Test
    fun `an adaptive Cindy names the mode instead of Cindy`() {
        val a = Attempt(
            rounds = 9, reps = 0, atMillis = 0L,
            profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP)
        )
        assertEquals("Adaptive Cindy — 9", StravaActivityText.name(a))
    }

    @Test
    fun `a lower-bound score is prefixed as at least`() {
        val a = Attempt(
            rounds = 14, reps = 3, atMillis = 0L, profile = CindyProfile.STANDARD,
            untrackedMs = 45_000L
        )
        assertTrue(a.scoreIsLowerBound)
        assertEquals("Cindy — at least 14 + 3", StravaActivityText.name(a))
    }

    // ---- description() -----------------------------------------------------------------------

    private val fullCindy = Attempt(
        rounds = 17, reps = 12, atMillis = 0L,
        durationMs = 20 * 60 * 1000L, countedReps = 522,
        profile = CindyProfile.STANDARD
    )

    @Test
    fun `the first line states rounds, reps, total and duration`() {
        val lines = StravaActivityText.description(fullCindy, CalorieBasis.NONE).lines()
        assertEquals("17 rounds + 12 reps · 522 reps in 20:00", lines[0])
    }

    @Test
    fun `one round and one rep are singular`() {
        val one = fullCindy.copy(rounds = 1, reps = 1, countedReps = 31)
        val lines = StravaActivityText.description(one, CalorieBasis.NONE).lines()
        assertEquals("1 round + 1 rep · 31 reps in 20:00", lines[0])
    }

    @Test
    fun `stopping before the clock runs out says so on the first line`() {
        val stopped = fullCindy.copy(durationMs = 12 * 60 * 1000L + 34_000L, countedReps = 300)
        val lines = StravaActivityText.description(stopped, CalorieBasis.NONE).lines()
        assertEquals("17 rounds + 12 reps · 300 reps in 12:34 — stopped early", lines[0])
    }

    @Test
    fun `a standard attempt's second line is its level caption`() {
        val lines = StravaActivityText.description(fullCindy, CalorieBasis.NONE).lines()
        assertEquals(fullCindy.caption, lines[1])
        assertEquals("Advanced", lines[1])
    }

    @Test
    fun `an adaptive attempt's second line names the changed movements`() {
        val adaptive = fullCindy.copy(profile = CindyProfile(push = PushVariant.KNEE_PUSH_UP))
        val lines = StravaActivityText.description(adaptive, CalorieBasis.NONE).lines()
        assertEquals("knee push-ups", lines[1])
    }

    @Test
    fun `an unrecognised profile's second line falls back to the caption`() {
        val unrecognised = fullCindy.copy(profile = null)
        val lines = StravaActivityText.description(unrecognised, CalorieBasis.NONE).lines()
        assertEquals("Movements not recognised", lines[1])
    }

    @Test
    fun `no line names round splits when there are none`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.NONE)
        assertFalse(description.contains("Average round"))
    }

    @Test
    fun `splits produce an average, fastest and slowest line`() {
        val withSplits = fullCindy.copy(
            roundSplitsMs = listOf(70_000L, 58_000L, 85_000L, 70_000L)
        )
        val description = StravaActivityText.description(withSplits, CalorieBasis.NONE)
        assertTrue(description.contains("Average round ${formatDuration(withSplits.avgRoundMs!!)}"))
        assertTrue(description.contains("fastest 0:58"))
        assertTrue(description.contains("slowest 1:25"))
    }

    @Test
    fun `no line mentions pausing when nothing was paused`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.NONE)
        assertFalse(description.contains("Paused"))
    }

    @Test
    fun `a pause names both the paused time and the real time`() {
        val paused = fullCindy.copy(pausedMs = 90_000L)
        val description = StravaActivityText.description(paused, CalorieBasis.NONE)
        assertTrue(description.contains("Paused 1:30 · 21:30 real time"))
    }

    @Test
    fun `no line mentions hand-added reps when none were added`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.NONE)
        assertFalse(description.contains("added by hand"))
    }

    @Test
    fun `manual reps are named against the total they contributed to`() {
        val manual = fullCindy.copy(manualReps = 12)
        val description = StravaActivityText.description(manual, CalorieBasis.NONE)
        assertTrue(description.contains("12 of the 522 reps were added by hand"))
    }

    @Test
    fun `no line claims a lower bound when the camera never lost the athlete`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.NONE)
        assertFalse(description.contains("lower bound"))
    }

    @Test
    fun `losing the camera is named and the score is called a lower bound`() {
        val blind = fullCindy.copy(untrackedMs = 45_000L)
        val description = StravaActivityText.description(blind, CalorieBasis.NONE)
        assertTrue(description.contains("The camera lost you for 0:45, so the score is a lower bound"))
    }

    @Test
    fun `no calorie line at all when there is nothing to base one on`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.NONE)
        assertFalse(description.contains("Calories"))
    }

    @Test
    fun `a body-weight calorie basis names the MET estimate`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.BODY_WEIGHT)
        val met = Calories.met(fullCindy.totalReps, fullCindy.durationMs)
        assertTrue(description.contains(String.format(Locale.US, "≈ %.1f METs", met)))
        assertTrue(description.contains("Calories estimated from body weight"))
    }

    @Test
    fun `a heart-rate calorie basis with full coverage says so plainly`() {
        val description = StravaActivityText.description(
            fullCindy, CalorieBasis.HEART_RATE, heartRateMs = fullCindy.durationMs
        )
        assertTrue(description.contains("Calories estimated from heart rate"))
    }

    @Test
    fun `a heart-rate calorie basis with no coverage given says so plainly`() {
        val description = StravaActivityText.description(fullCindy, CalorieBasis.HEART_RATE)
        assertTrue(description.contains("Calories estimated from heart rate"))
    }

    @Test
    fun `partial heart-rate coverage names the split with body weight`() {
        val description = StravaActivityText.description(
            fullCindy, CalorieBasis.HEART_RATE, heartRateMs = 14 * 60 * 1_000L + 20_000L
        )
        assertTrue(description.contains("Calories from heart rate for 14:20 of 20:00, body weight for the rest"))
    }

    @Test
    fun `the last line always credits the app`() {
        val lines = StravaActivityText.description(fullCindy, CalorieBasis.NONE).lines()
        assertEquals("Counted by Cindy Tracker", lines.last())
    }
}
