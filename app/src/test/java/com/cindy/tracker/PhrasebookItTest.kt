package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Italian lines where the grammar has something to get wrong: 1, the rest, and the clock. */
class PhrasebookItTest {

    private fun say(line: VoiceLine) = PhrasebookIt.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("trazioni", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("flessioni", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("squat", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `one is written out and the rest are counted`() {
        assertEquals("Un giro, 30 ripetizioni in totale", say(VoiceLine.Score(1, 30)))
        assertEquals("6 giri, 185 ripetizioni in totale", say(VoiceLine.Score(6, 185)))
        assertEquals("Una ripetizione", say(VoiceLine.Score(0, 1)))
        assertEquals("12 ripetizioni", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `durations`() {
        assertEquals("Giro 3 in un minuto e 20 secondi", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Giro 1 in 45 secondi", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Giro 2 in 2 minuti", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("In media un minuto e 20 secondi a giro", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals("Cinque minuti. Sei a 6 giri. Ritmo da 24 giri.", clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24))
        assertEquals("Metà tempo. Mantieni il tuo ritmo.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Mancano cinque minuti. Sei a un giro. Ritmo da un giro.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Due minuti. 6 giri, 185 ripetizioni in totale. Mantieni il ritmo.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Due minuti. 12 ripetizioni. Continua così.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Manca un minuto. Sei a 11 giri. Finisci quello in corso.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Dieci secondi. Dai tutto.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Registrazione tra 3 secondi", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Registrazione tra un secondo", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Registrazione in corso", say(VoiceLine.RecordingStarted))
        assertEquals("Registrazione non riuscita", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Italian`() {
        assertEquals("Afferra la sbarra", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Controlla la tua posizione", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
