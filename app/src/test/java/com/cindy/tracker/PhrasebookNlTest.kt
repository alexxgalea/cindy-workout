package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Dutch lines where the grammar has something to get wrong: 1, the rest, and the clock. */
class PhrasebookNlTest {

    private fun say(line: VoiceLine) = PhrasebookNl.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("optrekken", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("opdrukken", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("squats", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `one is written out and the rest are counted`() {
        assertEquals("Een ronde, 30 herhalingen in totaal", say(VoiceLine.Score(1, 30)))
        assertEquals("6 rondes, 185 herhalingen in totaal", say(VoiceLine.Score(6, 185)))
        assertEquals("Een herhaling", say(VoiceLine.Score(0, 1)))
        assertEquals("12 herhalingen", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `durations`() {
        assertEquals("Ronde 3 in een minuut en 20 seconden", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Ronde 1 in 45 seconden", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Ronde 2 in 2 minuten", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Gemiddeld een minuut en 20 seconden per ronde", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Vijf minuten bezig. Je hebt 6 rondes. Tempo voor 24 rondes.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Halverwege. Houd je tempo vast.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Nog vijf minuten. Je hebt een ronde. Tempo voor een ronde.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Twee minuten. 6 rondes, 185 herhalingen in totaal. Houd het tempo vast.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Twee minuten. 12 herhalingen. Ga door.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Nog een minuut. Je hebt 11 rondes. Maak de huidige ronde af.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Tien seconden. Geef alles.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Opname over 3 seconden", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Opname over een seconde", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Opname gestart", say(VoiceLine.RecordingStarted))
        assertEquals("Opname mislukt", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Dutch`() {
        assertEquals("Pak de stang", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Controleer je positie", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
