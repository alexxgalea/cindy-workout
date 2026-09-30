package com.cindy.tracker

/**
 * The voice in Dutch.
 *
 * Register: imperatives without a pronoun, which is neither formal nor informal. Plurals: one and
 * other. 1 is written out ("een ronde"), so a voice does not read a bare digit as a word of its
 * own. The movements use the Dutch names ("optrekken", "opdrukken") because a Dutch voice reads
 * the English "pull-ups" as if it were Dutch. Sentences end on a word, never on a number.
 *
 * Counts other than 1 are left as digits for the engine to agree with the noun that follows.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookNl : Phrasebook {

    override val tag = "nl"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "optrekken"
            Exercise.PUSHUP -> "opdrukken"
            Exercise.SQUAT -> "squats"
        }
        is VoiceLine.RoundDone -> "Ronde ${line.round} in ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "De telefoon is bewogen. Controleer het beeld."
        VoiceLine.SetUp -> "Ga in beeld en doe twee keer langzaam optrekken"
        is VoiceLine.Go -> if (line.calibrated) "Gekalibreerd. Start." else "Start. Optrekken"
        VoiceLine.Resume -> "Hervat"
        is VoiceLine.Finished -> if (line.early) "Gestopt." else "Tijd."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Gemiddeld ${duration(line.roundMs)} per ronde"
        is VoiceLine.BeatBenchmark -> "Je hebt ${line.name} verslagen"
        VoiceLine.Ready -> "Klaar"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Controleer je positie"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Drie. Vier. Vijf. Opdrukken."
        VoiceLine.VolumeCheck -> "Drie"
        is VoiceLine.RecordingSoon -> "Opname over ${seconds(line.seconds)}"
        VoiceLine.RecordingStarted -> "Opname gestart"
        VoiceLine.RecordingFailed -> "Opname mislukt"
        VoiceLine.AdaptiveHeelsFlat -> "Aangepaste Cindy ingeschakeld voor squats met de hielen op de grond."
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Ga in beeld staan"
        Hint.FINISH_SETUP_FIRST -> "Rond eerst de voorbereiding af"
        Hint.TRACKING -> "Ik zoek je"
        Hint.HANG_FROM_BAR -> "Hang aan de stang"
        Hint.HANG_VERTICALLY -> "Hang verticaal aan de stang"
        Hint.GET_ON_BAR -> "Pak de stang"
        Hint.SHOW_BOTH_HANDS -> "Laat allebei je handen zien"
        Hint.SHOW_YOUR_HEAD -> "Laat je hoofd zien"
        Hint.ARMS_OUT_OF_FRAME -> "Je armen zijn buiten beeld"
        Hint.GET_HEAD_OVER_BAR -> "Breng je hoofd boven de stang"
        Hint.RETURN_TO_DEAD_HANG -> "Hang weer met gestrekte armen"
        Hint.LOWER_ALL_THE_WAY -> "Ga helemaal omlaag"
        Hint.GET_SET_ON_FLOOR -> "Ga in positie op de grond"
        Hint.GET_ON_FLOOR -> "Ga op de grond"
        Hint.STAND_UP_TO_START -> "Sta op om te beginnen"
        Hint.SHOW_YOUR_LEGS -> "Laat je benen aan de camera zien"
        Hint.DRIVE_UP -> "Duw omhoog"
        Hint.GO_DOWN -> "Ga omlaag"
        Hint.LOSING_YOU -> "Ik verlies je uit beeld. Meer licht helpt."
        Hint.TOO_DARK -> "Te donker om te tellen. Tik op de knop plus één."
        Hint.CANT_SEE_YOU -> "Ik zie je niet. Tik op de knop plus één."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Tien seconden. Geef alles."
        ClockMark.ONE_MINUTE_LEFT ->
            "Nog een minuut. Je hebt ${rounds(line.rounds)}. Maak de huidige ronde af."
        ClockMark.TWO_MINUTES_LEFT -> "Twee minuten. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Nog vijf minuten. " + pace(line)
        ClockMark.HALFWAY -> "Halverwege. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Vijf minuten bezig. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Je hebt ${rounds(line.rounds)}. Tempo voor ${rounds(it)}." }
            ?: "Houd je tempo vast."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Ga door." else ". Houd het tempo vast."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} in totaal")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} en ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = noun(n, "een ronde", "rondes")
    private fun reps(n: Int) = noun(n, "een herhaling", "herhalingen")
    private fun minutes(n: Int) = noun(n, "een minuut", "minuten")
    private fun seconds(n: Int) = noun(n, "een seconde", "seconden")

    private fun noun(n: Int, one: String, other: String): String =
        if (Plurals.oneOther(n) == Plural.ONE) one else "$n $other"
}
