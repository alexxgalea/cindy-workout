package com.cindy.tracker

/**
 * The voice in Turkish.
 *
 * Register: the informal "sen", in short imperatives. Turkish has no plural after a numeral ("6
 * tur", "185 tekrar"), so there is no rule to follow and every count is a digit. The sentences are
 * built so that no suffix has to attach to the athlete's name or to a number: the benchmark is
 * "Tom Holland skorunu", where the possessive lands on "skor" and the name stays as it is.
 * Sentences end on a word, never on a number: Turkish engines read "12." as an ordinal.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookTr : Phrasebook {

    override val tag = "tr"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "barfiks"
            Exercise.PUSHUP -> "şınav"
            Exercise.SQUAT -> "squat"
        }
        is VoiceLine.RoundDone -> "Tur ${line.round}, süre ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Telefon kımıldadı. Kadrajı kontrol et."
        VoiceLine.SetUp -> "Kadraja gir, sonra iki yavaş barfiks yap"
        is VoiceLine.Go -> if (line.calibrated) "Kalibre edildi. Başla." else "Başla. Barfiks"
        VoiceLine.Resume -> "Devam"
        is VoiceLine.Finished -> if (line.early) "Durduruldu." else "Süre doldu."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Tur başına ortalama ${duration(line.roundMs)}"
        is VoiceLine.BeatBenchmark -> "${line.name} skorunu geçtin"
        VoiceLine.Ready -> "Hazır"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Pozisyonunu kontrol et"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Üç. Dört. Beş. Şınav."
        VoiceLine.VolumeCheck -> "Üç"
        is VoiceLine.RecordingSoon -> "Kayıt ${line.seconds} saniye sonra başlıyor"
        VoiceLine.RecordingStarted -> "Kayıt başladı"
        VoiceLine.RecordingFailed -> "Kayıt başarısız"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Kadraja gir"
        Hint.FINISH_SETUP_FIRST -> "Önce hazırlığı bitir"
        Hint.TRACKING -> "Seni arıyorum"
        Hint.HANG_FROM_BAR -> "Barfikse asıl"
        Hint.HANG_VERTICALLY -> "Barfikse dik şekilde asıl"
        Hint.GET_ON_BAR -> "Barı tut"
        Hint.SHOW_BOTH_HANDS -> "İki elini de göster"
        Hint.SHOW_YOUR_HEAD -> "Kafanı göster"
        Hint.ARMS_OUT_OF_FRAME -> "Kolların kadrajın dışında"
        Hint.GET_HEAD_OVER_BAR -> "Başını barın üstüne çıkar"
        Hint.RETURN_TO_DEAD_HANG -> "Kollarını düzleyip yeniden asıl"
        Hint.LOWER_ALL_THE_WAY -> "Tamamen aşağı in"
        Hint.GET_SET_ON_FLOOR -> "Yerde pozisyon al"
        Hint.GET_ON_FLOOR -> "Yere geç"
        Hint.STAND_UP_TO_START -> "Başlamak için ayağa kalk"
        Hint.SHOW_YOUR_LEGS -> "Bacaklarını kameraya göster"
        Hint.DRIVE_UP -> "Yukarı it"
        Hint.GO_DOWN -> "Aşağı in"
        Hint.LOSING_YOU -> "Seni gözden kaybediyorum. Daha fazla ışık yardımcı olur."
        Hint.TOO_DARK -> "Saymak için çok karanlık. Artı bir düğmesine dokun."
        Hint.CANT_SEE_YOU -> "Seni göremiyorum. Artı bir düğmesine dokun."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "On saniye. Bütün gücünle."
        ClockMark.ONE_MINUTE_LEFT ->
            "Bir dakika kaldı. ${line.rounds} tur tamamlandı. Başladığın turu bitir."
        ClockMark.TWO_MINUTES_LEFT -> "İki dakika. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Beş dakika kaldı. " + pace(line)
        ClockMark.HALFWAY -> "Yarı yol. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Beş dakika geçti. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "${line.rounds} tur tamamlandı. Bu tempoyla $it tur." }
            ?: "Tempoyu koru."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Devam et." else ". Tempoyu koru."

    private fun score(rounds: Int, totalReps: Int): String =
        if (rounds < 1) "$totalReps tekrar" else "$rounds tur, toplam $totalReps tekrar"

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> "$s saniye"
            s == 0 -> "$m dakika"
            else -> "$m dakika $s saniye"
        }
    }
}
