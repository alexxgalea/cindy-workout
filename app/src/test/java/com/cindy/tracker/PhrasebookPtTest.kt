package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Portuguese lines where the grammar has something to get wrong: 1, 2, nought, and the clock. */
class PhrasebookPtTest {

    private fun say(line: VoiceLine) = PhrasebookPt.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("barras", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("flexões", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("agachamentos", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `one and two are written out for the feminine nouns`() {
        assertEquals("Uma rodada, 30 repetições no total", say(VoiceLine.Score(1, 30)))
        assertEquals("Duas rodadas, 60 repetições no total", say(VoiceLine.Score(2, 60)))
        assertEquals("6 rodadas, 185 repetições no total", say(VoiceLine.Score(6, 185)))
        assertEquals("Uma repetição", say(VoiceLine.Score(0, 1)))
        assertEquals("Duas repetições", say(VoiceLine.Score(0, 2)))
        assertEquals("12 repetições", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `nought is singular`() {
        assertEquals("0 repetição", say(VoiceLine.Score(0, 0)))
    }

    @Test
    fun `durations`() {
        assertEquals("Rodada 3 em um minuto e 20 segundos", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Rodada 1 em 45 segundos", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Rodada 2 em 2 minutos", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Rodada 12 em um minuto e um segundo", say(VoiceLine.RoundDone(12, 61_000L)))
        assertEquals("Média de um minuto e 20 segundos por rodada", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Cinco minutos. Você tem 6 rodadas. Ritmo para 24 rodadas.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Metade do tempo. Mantenha o seu ritmo.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Faltam cinco minutos. Você tem duas rodadas. Ritmo para uma rodada.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 2, 60, 1)
        )
        assertEquals(
            "Dois minutos. 6 rodadas, 185 repetições no total. Mantenha o ritmo.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Dois minutos. 12 repetições. Continue.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Falta um minuto. Você tem 11 rodadas. Termine a que está fazendo.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Dez segundos. Dê tudo o que tem.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Gravando em 3 segundos", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Gravando em um segundo", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Gravando", say(VoiceLine.RecordingStarted))
        assertEquals("Falha na gravação", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Portuguese`() {
        assertEquals("Segure a barra", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Confira a sua posição", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
