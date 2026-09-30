package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The words the voice has always said, held byte for byte.
 *
 * Every expected string here is what the app said before the voice went through phrasebooks —
 * the literals that lived in [MainActivity] and [Coach]. Making the voice multilingual is only
 * safe if English cannot change underneath it, and nothing else would notice: these are lines
 * that are spoken once a workout, over a screen nobody is looking at.
 */
class PhrasebookEnTest {

    private fun say(line: VoiceLine) = PhrasebookEn.say(line)

    @Test
    fun `a count is the bare number`() {
        assertEquals("0", say(VoiceLine.Count(0)))
        assertEquals("3", say(VoiceLine.Count(3)))
        assertEquals("15", say(VoiceLine.Count(15)))
    }

    @Test
    fun `movements are the names the engine carries`() {
        assertEquals("pull ups", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("push ups", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("squats", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `a round names its number and its time`() {
        assertEquals("Round 3 in 1 minute 20", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Round 1 in 45 seconds", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Round 12 in 2 minutes", say(VoiceLine.RoundDone(12, 120_000L)))
    }

    @Test
    fun `durations are said the way a person says them`() {
        assertEquals("45 seconds", PhrasebookEn.duration(45_000L))
        assertEquals("1 minute", PhrasebookEn.duration(60_000L))
        assertEquals("2 minutes", PhrasebookEn.duration(120_000L))
        assertEquals("1 minute 1", PhrasebookEn.duration(61_000L))
        assertEquals("2 minutes 30", PhrasebookEn.duration(150_000L))
        // Sub-second remainders are dropped, not rounded up.
        assertEquals("1 minute 20", PhrasebookEn.duration(80_999L))
    }

    @Test
    fun `the fixed announcements`() {
        assertEquals("Phone moved. Check the framing.", say(VoiceLine.PhoneMoved))
        assertEquals("Get in frame, then do two slow pull ups", say(VoiceLine.SetUp))
        assertEquals("Resume", say(VoiceLine.Resume))
        assertEquals("Ready", say(VoiceLine.Ready))
    }

    @Test
    fun `the start says whether the check was passed`() {
        assertEquals("Calibrated. Go.", say(VoiceLine.Go(calibrated = true)))
        assertEquals("Go. Pull ups", say(VoiceLine.Go(calibrated = false)))
    }

    @Test
    fun `the end says whether the athlete called it`() {
        assertEquals("Time.", say(VoiceLine.Finished(early = false)))
        assertEquals("Stopped.", say(VoiceLine.Finished(early = true)))
    }

    @Test
    fun `the average round and the benchmark`() {
        assertEquals("Averaging 1 minute 20 a round", say(VoiceLine.Averaging(80_000L)))
        assertEquals("You beat Tom Holland", say(VoiceLine.BeatBenchmark("Tom Holland")))
    }

    @Test
    fun `a fault is the engine's hint, untouched`() {
        assertEquals("Get on the bar", say(VoiceLine.Fault("Get on the bar")))
        // Including one nobody has catalogued: English never invents a sentence.
        assertEquals("Something new", say(VoiceLine.Fault("Something new")))
    }

    @Test
    fun `a score names the rounds and the whole rep tally`() {
        assertEquals("6 rounds — 185 reps in total", say(VoiceLine.Score(6, 185)))
        assertEquals("1 round — 30 reps in total", say(VoiceLine.Score(1, 30)))
        // Before a round is in there is nothing to name but the reps.
        assertEquals("12 reps", say(VoiceLine.Score(0, 12)))
        assertEquals("1 rep", say(VoiceLine.Score(0, 1)))
    }

    @Test
    fun `a finished round is never reported as zero reps`() {
        // The bug this exists to stop: the score was read off the reps of the round in
        // progress, which a completed round leaves at zero. One clean round is thirty reps of
        // work and was being announced as none, over a results screen reading thirty.
        val said = say(VoiceLine.Score(rounds = 1, totalReps = 30))
        assertTrue(said, said.contains("30 reps"))
        // Word-boundary, because "30 reps" contains "0 reps" as plain text.
        assertFalse(said, Regex("\\b0 reps").containsMatchIn(said))
    }

    @Test
    fun `the clock marks`() {
        fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
            say(VoiceLine.Clock(mark, rounds, reps, projected))

        assertEquals(
            "Five minutes in. 6 rounds — on for 24.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Halfway. 6 rounds — on for 12.", clock(ClockMark.HALFWAY, 6, 185, 12))
        assertEquals(
            "Five minutes left. 1 round — on for 2.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 2)
        )
        assertEquals(
            "Two minutes. 6 rounds — 185 reps in total. Hold the pace.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals(
            "One minute left. 11 rounds down — finish the one you're in.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals(
            "One minute left. 1 round down — finish the one you're in.",
            clock(ClockMark.ONE_MINUTE_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Ten seconds. Everything you have.",
            clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12)
        )
    }

    @Test
    fun `the clock has nothing to project before a round is in`() {
        fun clock(mark: ClockMark) = say(VoiceLine.Clock(mark, 0, 0, null))

        assertEquals("Halfway. Keep the pace you're on.", clock(ClockMark.HALFWAY))
        assertEquals("Five minutes in. Keep the pace you're on.", clock(ClockMark.FIVE_MINUTES_IN))
        assertEquals("Five minutes left. Keep the pace you're on.", clock(ClockMark.FIVE_MINUTES_LEFT))
        assertEquals("Two minutes. 0 reps. Keep going.", clock(ClockMark.TWO_MINUTES_LEFT))
    }

    @Test
    fun `the menu's samples`() {
        assertEquals("Three. Four. Five. Push ups.", say(VoiceLine.Sample))
        assertEquals("Three", say(VoiceLine.VolumeCheck))
    }

    @Test
    fun `recording is announced in words, never as a bare number`() {
        // Beside the rep counts a lone "3" would be taken for one.
        assertEquals("Recording in 3", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Recording", say(VoiceLine.RecordingStarted))
        assertEquals("Recording didn't start", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `every line is said in words`() {
        VoiceLineSamples.all.forEach { line ->
            assertTrue("$line was blank", say(line).isNotBlank())
        }
    }

    @Test
    fun `the samples cover every kind of line`() {
        assertEquals(
            "a kind of line has no sample, or KINDS is out of date",
            VoiceLineSamples.KINDS,
            VoiceLineSamples.all.map { it.javaClass }.toSet().size
        )
    }
}
