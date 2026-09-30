package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The French lines where the grammar has something to get wrong: nought and one, and the clock. */
class PhrasebookFrTest {

    private fun say(line: VoiceLine) = PhrasebookFr.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("tractions", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("pompes", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("squats", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `nought and one are both singular`() {
        assertEquals("Un tour, 30 répétitions au total", say(VoiceLine.Score(1, 30)))
        assertEquals("2 tours, 60 répétitions au total", say(VoiceLine.Score(2, 60)))
        assertEquals("6 tours, 185 répétitions au total", say(VoiceLine.Score(6, 185)))
        assertEquals("Une répétition", say(VoiceLine.Score(0, 1)))
        assertEquals("0 répétition", say(VoiceLine.Score(0, 0)))
        assertEquals("12 répétitions", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `durations`() {
        assertEquals("Tour 3 en une minute et 20 secondes", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Tour 1 en 45 secondes", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Tour 2 en 2 minutes", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Tour 12 en une minute et une seconde", say(VoiceLine.RoundDone(12, 61_000L)))
        assertEquals("En moyenne, une minute et 20 secondes par tour", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Cinq minutes. Tu en es à 6 tours. Rythme pour 24 tours.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("À mi-parcours. Garde ton rythme.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Il reste cinq minutes. Tu en es à un tour. Rythme pour un tour.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Deux minutes. 6 tours, 185 répétitions au total. Garde le rythme.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Deux minutes. 12 répétitions. Continue.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Il reste une minute. Tu en es à 11 tours. Termine celui en cours.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Dix secondes. Donne tout.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Enregistrement dans 3 secondes", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Enregistrement dans une seconde", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Enregistrement en cours", say(VoiceLine.RecordingStarted))
        assertEquals("L'enregistrement a échoué", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something French`() {
        assertEquals("Attrape la barre", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Vérifie ta position", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
