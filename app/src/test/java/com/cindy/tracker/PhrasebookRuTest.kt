package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The Russian lines where the grammar has something to get wrong: the one/few/many forms at the
 * counts where they change (1, 2, 5, 11, 21, 22), written-out 1 and 2, and the accusative.
 */
class PhrasebookRuTest {

    private fun say(line: VoiceLine) = PhrasebookRu.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("подтягивания", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("отжимания", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("приседания", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `rounds take the form their count asks for`() {
        assertEquals("1 раунд, всего 30 повторений", say(VoiceLine.Score(1, 30)))
        assertEquals("2 раунда, всего 60 повторений", say(VoiceLine.Score(2, 60)))
        assertEquals("5 раундов, всего 150 повторений", say(VoiceLine.Score(5, 150)))
        // Eleven is not "one" and twenty-one is: the last two digits decide.
        assertEquals("11 раундов, всего 330 повторений", say(VoiceLine.Score(11, 330)))
        assertEquals("21 раунд, всего 630 повторений", say(VoiceLine.Score(21, 630)))
        assertEquals("22 раунда, всего 660 повторений", say(VoiceLine.Score(22, 660)))
    }

    @Test
    fun `repetitions are neuter and follow the same counts`() {
        assertEquals("Одно повторение", say(VoiceLine.Score(0, 1)))
        assertEquals("2 повторения", say(VoiceLine.Score(0, 2)))
        assertEquals("5 повторений", say(VoiceLine.Score(0, 5)))
        assertEquals("11 повторений", say(VoiceLine.Score(0, 11)))
        assertEquals("21 повторение", say(VoiceLine.Score(0, 21)))
    }

    @Test
    fun `durations`() {
        assertEquals("Раунд 3, время одна минута и 20 секунд", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Раунд 2, время две минуты и 5 секунд", say(VoiceLine.RoundDone(2, 125_000L)))
        assertEquals("Раунд 1, время 45 секунд", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Раунд 4, время 3 минуты", say(VoiceLine.RoundDone(4, 180_000L)))
        assertEquals("Раунд 5, время 5 минут", say(VoiceLine.RoundDone(5, 300_000L)))
        assertEquals("Раунд 6, время 21 секунда", say(VoiceLine.RoundDone(6, 21_000L)))
        assertEquals("В среднем одна минута и 20 секунд на раунд", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the benchmark is a comparison in the present tense`() {
        // No "побил" or "побила": the sentence is true whoever is listening.
        assertEquals("Результат лучше, чем у Tom Holland", say(VoiceLine.BeatBenchmark("Tom Holland")))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Прошло пять минут. Раундов: 6, темп на 24 раунда.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Половина времени. Раундов: 6, темп на 12 раундов.", clock(ClockMark.HALFWAY, 6, 185, 12))
        assertEquals("Половина времени. Держи свой темп.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "Осталось пять минут. Раундов: 1, темп на 1 раунд.",
            clock(ClockMark.FIVE_MINUTES_LEFT, 1, 30, 1)
        )
        assertEquals(
            "Две минуты. 6 раундов, всего 185 повторений. Держи темп.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("Две минуты. 12 повторений. Продолжай.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Осталась минута. Раундов: 11, закончи текущий.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Десять секунд. Выложись полностью.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording puts the seconds in the accusative`() {
        assertEquals("Запись через одну секунду", say(VoiceLine.RecordingSoon(1)))
        assertEquals("Запись через две секунды", say(VoiceLine.RecordingSoon(2)))
        assertEquals("Запись через 3 секунды", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Запись через 5 секунд", say(VoiceLine.RecordingSoon(5)))
        assertEquals("Запись через 21 секунду", say(VoiceLine.RecordingSoon(21)))
        assertEquals("Идёт запись", say(VoiceLine.RecordingStarted))
        assertEquals("Запись не удалась", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Russian`() {
        assertEquals("Возьмись за перекладину", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Проверь своё положение", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
