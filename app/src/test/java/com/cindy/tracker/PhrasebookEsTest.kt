package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Spanish lines where the grammar has something to get wrong: 1, the rest, and the clock. */
class PhrasebookEsTest {

    private fun say(line: VoiceLine) = PhrasebookEs.say(line)

    @Test
    fun `movements`() {
        assertEquals("dominadas", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("flexiones", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("sentadillas", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `one is written out and the rest are counted`() {
        assertEquals("Una ronda, 30 repeticiones en total", say(VoiceLine.Score(1, 30)))
        assertEquals("6 rondas, 185 repeticiones en total", say(VoiceLine.Score(6, 185)))
        assertEquals("Una repetición", say(VoiceLine.Score(0, 1)))
        assertEquals("12 repeticiones", say(VoiceLine.Score(0, 12)))
        assertEquals("0 repeticiones", say(VoiceLine.Score(0, 0)))
    }

    @Test
    fun `durations`() {
        assertEquals("Ronda 3 en un minuto y 20 segundos", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Ronda 1 en 45 segundos", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Ronda 2 en 2 minutos", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Ronda 12 en un minuto y un segundo", say(VoiceLine.RoundDone(12, 61_000L)))
        assertEquals("De media, un minuto y 20 segundos por ronda", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
            say(VoiceLine.Clock(mark, rounds, reps, projected))

        assertEquals("Cinco minutos. Llevas 6 rondas. Ritmo para 24 rondas.", clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24))
        assertEquals("A mitad de camino. Mantén tu ritmo.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals("Quedan cinco minutos. Llevas una ronda. Ritmo para una ronda.", clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1))
        assertEquals(
            "Dos minutos. 6 rondas, 185 repeticiones en total. Mantén el ritmo.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Dos minutos. 12 repeticiones. Sigue así.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Queda un minuto. Llevas 11 rondas. Termina la que estás haciendo.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Diez segundos. Todo lo que tengas.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Grabando en 3 segundos", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Grabando en un segundo", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Grabando", say(VoiceLine.RecordingStarted))
        assertEquals("Falló la grabación", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Spanish`() {
        assertEquals("Agárrate a la barra", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Revisa tu posición", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
