package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The German lines where the grammar has something to get wrong: 1, the dative, and the clock. */
class PhrasebookDeTest {

    private fun say(line: VoiceLine) = PhrasebookDe.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("Klimmzüge", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("Liegestütze", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("Kniebeugen", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `one is written out and the rest are counted`() {
        assertEquals("Eine Runde, 30 Wiederholungen insgesamt", say(VoiceLine.Score(1, 30)))
        assertEquals("6 Runden, 185 Wiederholungen insgesamt", say(VoiceLine.Score(6, 185)))
        assertEquals("Eine Wiederholung", say(VoiceLine.Score(0, 1)))
        assertEquals("12 Wiederholungen", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `a round's time follows Zeit so the count stays nominative`() {
        assertEquals("Runde 3, Zeit eine Minute und 20 Sekunden", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Runde 1, Zeit 45 Sekunden", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Runde 2, Zeit 2 Minuten", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Im Schnitt eine Minute und 20 Sekunden pro Runde", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Fünf Minuten sind um. 6 Runden geschafft. Tempo für 24 Runden.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Halbzeit. Halte dein Tempo.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Noch fünf Minuten. Eine Runde geschafft. Tempo für eine Runde.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Zwei Minuten. 6 Runden, 185 Wiederholungen insgesamt. Halte das Tempo.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Zwei Minuten. 12 Wiederholungen. Weiter so.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Noch eine Minute. Eine Runde geschafft. Beende die laufende Runde.",
            clock(ClockMark.ONE_MINUTE_LEFT, 1, 30, 1)
        )
        assertEquals("Zehn Sekunden. Gib alles.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording puts a single second in the dative`() {
        assertEquals("Aufnahme in 3 Sekunden", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Aufnahme in einer Sekunde", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Aufnahme läuft", say(VoiceLine.RecordingStarted))
        assertEquals("Aufnahme fehlgeschlagen", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something German`() {
        assertEquals("Greif die Stange", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Prüfe deine Position", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
