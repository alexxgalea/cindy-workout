package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Turkish lines: no plural to get wrong, so what is pinned is the shape of each sentence. */
class PhrasebookTrTest {

    private fun say(line: VoiceLine) = PhrasebookTr.say(line)

    private fun clock(mark: ClockMark, rounds: Int, reps: Int, projected: Int?) =
        say(VoiceLine.Clock(mark, rounds, reps, projected))

    @Test
    fun `movements`() {
        assertEquals("barfiks", say(VoiceLine.Movement(Exercise.PULLUP)))
        assertEquals("şınav", say(VoiceLine.Movement(Exercise.PUSHUP)))
        assertEquals("squat", say(VoiceLine.Movement(Exercise.SQUAT)))
    }

    @Test
    fun `a noun stays singular after a numeral`() {
        assertEquals("1 tur, toplam 30 tekrar", say(VoiceLine.Score(1, 30)))
        assertEquals("6 tur, toplam 185 tekrar", say(VoiceLine.Score(6, 185)))
        assertEquals("12 tekrar", say(VoiceLine.Score(0, 12)))
    }

    @Test
    fun `durations`() {
        assertEquals("Tur 3, süre 1 dakika 20 saniye", say(VoiceLine.RoundDone(3, 80_000L)))
        assertEquals("Tur 1, süre 45 saniye", say(VoiceLine.RoundDone(1, 45_000L)))
        assertEquals("Tur 2, süre 2 dakika", say(VoiceLine.RoundDone(2, 120_000L)))
        assertEquals("Tur başına ortalama 1 dakika 20 saniye", say(VoiceLine.Averaging(80_000L)))
    }

    @Test
    fun `the benchmark keeps the name as it is`() {
        // The possessive lands on "skor", so no suffix has to attach to the athlete's name.
        assertEquals("Tom Holland skorunu geçtin", say(VoiceLine.BeatBenchmark("Tom Holland")))
    }

    @Test
    fun `the clock marks`() {
        assertEquals(
            "Beş dakika geçti. 6 tur tamamlandı. Bu tempoyla 24 tur.",
            clock(ClockMark.FIVE_MINUTES_IN, 6, 185, 24)
        )
        assertEquals("Yarı yol. Tempoyu koru.", clock(ClockMark.HALFWAY, 0, 0, null))
        assertEquals(
            "İki dakika. 6 tur, toplam 185 tekrar. Tempoyu koru.",
            clock(ClockMark.TWO_MINUTES_LEFT, 6, 185, 12)
        )
        assertEquals("İki dakika. 12 tekrar. Devam et.", clock(ClockMark.TWO_MINUTES_LEFT, 0, 12, null))
        assertEquals(
            "Bir dakika kaldı. 11 tur tamamlandı. Başladığın turu bitir.",
            clock(ClockMark.ONE_MINUTE_LEFT, 11, 340, 11)
        )
        assertEquals("Beş dakika kaldı. Tempoyu koru.", clock(ClockMark.FIVE_MINUTES_LEFT, 0, 0, null))
        assertEquals("On saniye. Bütün gücünle.", clock(ClockMark.TEN_SECONDS_LEFT, 6, 185, 12))
    }

    @Test
    fun `recording`() {
        assertEquals("Kayıt 3 saniye sonra başlıyor", say(VoiceLine.RecordingSoon(3)))
        assertEquals("Kayıt başladı", say(VoiceLine.RecordingStarted))
        assertEquals("Kayıt başarısız", say(VoiceLine.RecordingFailed))
    }

    @Test
    fun `a hint is translated and an unknown one falls back to something Turkish`() {
        assertEquals("Barı tut", say(VoiceLine.Fault("Get on the bar")))
        assertEquals("Pozisyonunu kontrol et", say(VoiceLine.Fault("Something nobody catalogued")))
    }
}
