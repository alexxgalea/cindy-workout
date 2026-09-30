package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The Romanian lines where the grammar has something to get wrong: "few" up to 19, "de" from 20,
 * and written-out 1 and 2.
 */
class PhrasebookRoTest {

    private fun say(line: VoiceLine) = PhrasebookRo.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("tracțiuni", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("flotări", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("genuflexiuni", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `counts take de from twenty`() {
        assertEquals("O rundă, 30 de repetări în total", say(VoiceLine.Score(1, 30)))
        assertEquals("Două runde, 60 de repetări în total", say(VoiceLine.Score(2, 60)))
        assertEquals("6 runde, 185 de repetări în total", say(VoiceLine.Score(6, 185)))
        assertEquals("19 runde, 570 de repetări în total", say(VoiceLine.Score(19, 570)))
        assertEquals("20 de runde, 600 de repetări în total", say(VoiceLine.Score(20, 600)))
        // 101 to 119 are "few" again, and 3030 is "other" because of its last two digits.
        assertEquals("101 runde, 3030 de repetări în total", say(VoiceLine.Score(101, 3030)))
    }

    @Test
    fun `repetitions before a round is in`() {
        assertEquals("O repetare", say(VoiceLine.Score(0, 1)))
        assertEquals("12 repetări", say(VoiceLine.Score(0, 12)))
        assertEquals("20 de repetări", say(VoiceLine.Score(0, 20)))
        // Nought is "few" in Romanian, unlike English, French or Portuguese.
        assertEquals("0 repetări", say(VoiceLine.Score(0, 0)))
    }

    @Test
    fun `durations`() {
        assertEquals("Runda 3, timp de un minut și 20 de secunde", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Runda 1, timp de 45 de secunde", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Runda 2, timp de două minute", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Runda 5, timp de un minut și 5 secunde", say(VoiceLine.RoundDone(5, 65_000L)))
        assertEquals("Runda 6, timp de 5 minute", say(VoiceLine.RoundDone(6, 300_000L)))
        assertEquals("În medie un minut și 20 de secunde pe rundă", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Cinci minute. Ai 6 runde. Ritm pentru 24 de runde.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("La jumătate. Ține-ți ritmul.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Mai sunt cinci minute. Ai o rundă. Ritm pentru o rundă.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Două minute. 6 runde, 185 de repetări în total. Ține ritmul.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Două minute. 12 repetări. Continuă.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Mai e un minut. Ai 20 de runde. Termină runda în curs.",
            clock(ClockMark.ONE_MINUTE_LEFT, 20, 600, 20)
        )
        assertEquals("Zece secunde. Dă tot ce ai.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording contracts a single second`() {
        assertEquals("Înregistrare în 3 secunde", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Înregistrare într-o secundă", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Înregistrare în 20 de secunde", say(VoiceLine.RecordingSoon(20)))
        assertEquals("Se înregistrează", say(VoiceLine.RecordingStarted))
        assertEquals("Înregistrarea a eșuat", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Romanian`() {
        assertEquals("Prinde bara", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Verifică-ți poziția", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
