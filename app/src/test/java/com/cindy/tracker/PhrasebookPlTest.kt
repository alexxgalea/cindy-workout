package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The Polish lines where the grammar has something to get wrong: the one/few/many forms at the
 * counts where they change (1, 2, 5, 12, 22), written-out 1 and 2, and the accusatives.
 */
class PhrasebookPlTest {

    private fun say(line: VoiceLine) = PhrasebookPl.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("podciągnięcia", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("pompki", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("przysiady", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `rounds take the form their count asks for`() {
        assertEquals("Jedna runda, łącznie 30 powtórzeń", say(VoiceLine.Score(1, 30)))
        assertEquals("Dwie rundy, łącznie 60 powtórzeń", say(VoiceLine.Score(2, 60)))
        assertEquals("3 rundy, łącznie 90 powtórzeń", say(VoiceLine.Score(3, 90)))
        assertEquals("5 rund, łącznie 150 powtórzeń", say(VoiceLine.Score(5, 150)))
        assertEquals("12 rund, łącznie 360 powtórzeń", say(VoiceLine.Score(12, 360)))
        assertEquals("22 rundy, łącznie 660 powtórzeń", say(VoiceLine.Score(22, 660)))
    }

    @Test
    fun `repetitions are neuter and follow the same counts`() {
        assertEquals("Jedno powtórzenie", say(VoiceLine.Score(0, 1)))
        assertEquals("2 powtórzenia", say(VoiceLine.Score(0, 2)))
        assertEquals("5 powtórzeń", say(VoiceLine.Score(0, 5)))
        assertEquals("12 powtórzeń", say(VoiceLine.Score(0, 12)))
        assertEquals("22 powtórzenia", say(VoiceLine.Score(0, 22)))
    }

    @Test
    fun `durations`() {
        assertEquals("Runda 3, czas jedna minuta i 20 sekund", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Runda 2, czas dwie minuty i 5 sekund", say(VoiceLine.RoundDone(2, 125_000L)))
        assertEquals("Runda 1, czas 45 sekund", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Runda 4, czas 3 minuty", say(VoiceLine.RoundDone(4, 180_000L)))
        assertEquals("Runda 5, czas 5 minut", say(VoiceLine.RoundDone(5, 300_000L)))
        assertEquals("Średnio jedna minuta i 20 sekund na rundę", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Pięć minut za nami. Ukończone rundy: 6, tempo na 24 rundy.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Połowa czasu. Ukończone rundy: 6, tempo na 12 rund.", clock(ClockMark.HALFWAY, 6, 185, 12))
        assertEquals("Połowa czasu. Utrzymaj swoje tempo.", clock(ClockMark.HALFWAY, 0, 0, null))
        // A single round is accusative after "na".
        assertEquals(
            "Zostało pięć minut. Ukończone rundy: 1, tempo na jedną rundę.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Dwie minuty. 6 rund, łącznie 185 powtórzeń. Utrzymaj tempo.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Dwie minuty. 12 powtórzeń. Dalej.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Została minuta. Ukończone rundy: 11, dokończ bieżącą.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Dziesięć sekund. Daj z siebie wszystko.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording puts the seconds in the accusative`() {
        assertEquals("Nagrywanie za 3 sekundy", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Nagrywanie za jedną sekundę", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Nagrywanie za dwie sekundy", say(VoiceLine.RecordingSoon(2)))
        assertEquals("Nagrywanie za 5 sekund", say(VoiceLine.RecordingSoon(5)))
        assertEquals("Nagrywanie rozpoczęte", say(VoiceLine.RecordingStarted))
        assertEquals("Nagrywanie nie powiodło się", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `the benchmark is a comparison with no case to get wrong`() {
        assertEquals("Wynik lepszy niż Tom Holland", say(VoiceLine.BeatBenchmark("Tom Holland")))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Polish`() {
        assertEquals("Chwyć drążek", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Sprawdź swoją pozycję", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
