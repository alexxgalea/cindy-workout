package com.cindy.tracker

/**
 * The voice in Romanian.
 *
 * Register: the informal "tu", in short imperatives. Plurals: one, few and other. "Few" covers 0
 * and 2–19 (and 101–119), and from 20 the noun takes "de": "2 runde" but "20 de runde" and
 * "120 de runde". 1 and 2 are written out ("o rundă", "două runde") because a voice does not
 * agree the numeral's gender with the noun after a digit. The duration follows "timp de" rather
 * than "în", since "în un minut" contracts to "într-un minut". Sentences end on a word, never on
 * a number: Romanian engines read "12." as an ordinal.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookRo : Phrasebook {

    override val tag = "ro"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "tracțiuni"
            Exercise.PUSHUP -> "flotări"
            Exercise.SQUAT -> "genuflexiuni"
        }
        is VoiceLine.RoundDone -> "Runda ${line.round}, timp de ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Telefonul s-a mișcat. Verifică cadrul."
        VoiceLine.SetUp -> "Intră în cadru, apoi fă două tracțiuni lente"
        is VoiceLine.Go -> if (line.calibrated) "Calibrat. Start." else "Start. Tracțiuni"
        VoiceLine.Resume -> "Reluăm"
        is VoiceLine.Finished -> if (line.early) "Oprit." else "Timpul a expirat."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "În medie ${duration(line.roundMs)} pe rundă"
        is VoiceLine.BeatBenchmark -> "L-ai depășit pe ${line.name}"
        VoiceLine.Ready -> "Gata"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Verifică-ți poziția"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Trei. Patru. Cinci. Flotări."
        VoiceLine.VolumeCheck -> "Trei"
        is VoiceLine.RecordingSoon -> recordingSoon(line.seconds)
        VoiceLine.RecordingStarted -> "Se înregistrează"
        VoiceLine.RecordingFailed -> "Înregistrarea a eșuat"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Intră în cadru"
        Hint.FINISH_SETUP_FIRST -> "Termină mai întâi pregătirea"
        Hint.TRACKING -> "Te caut"
        Hint.HANG_FROM_BAR -> "Agață-te de bară"
        Hint.HANG_VERTICALLY -> "Agață-te de bară, pe verticală"
        Hint.GET_ON_BAR -> "Prinde bara"
        Hint.SHOW_BOTH_HANDS -> "Arată ambele mâini"
        Hint.SHOW_YOUR_HEAD -> "Arată-ți capul"
        Hint.ARMS_OUT_OF_FRAME -> "Brațele ies din cadru"
        Hint.GET_HEAD_OVER_BAR -> "Ridică capul deasupra barei"
        Hint.RETURN_TO_DEAD_HANG -> "Revino în atârnare, cu brațele întinse"
        Hint.LOWER_ALL_THE_WAY -> "Coboară complet"
        Hint.GET_SET_ON_FLOOR -> "Ia poziția pe podea"
        Hint.GET_ON_FLOOR -> "Așază-te pe podea"
        Hint.STAND_UP_TO_START -> "Ridică-te ca să începi"
        Hint.SHOW_YOUR_LEGS -> "Arată-ți picioarele camerei"
        Hint.DRIVE_UP -> "Împinge în sus"
        Hint.GO_DOWN -> "Coboară"
        Hint.LOSING_YOU -> "Te pierd din vedere. Mai multă lumină ajută."
        Hint.TOO_DARK -> "Prea întuneric ca să număr. Atinge butonul plus unu."
        Hint.CANT_SEE_YOU -> "Nu te văd. Atinge butonul plus unu."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Zece secunde. Dă tot ce ai."
        ClockMark.ONE_MINUTE_LEFT ->
            "Mai e un minut. Ai ${rounds(line.rounds)}. Termină runda în curs."
        ClockMark.TWO_MINUTES_LEFT -> "Două minute. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Mai sunt cinci minute. " + pace(line)
        ClockMark.HALFWAY -> "La jumătate. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Cinci minute. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Ai ${rounds(line.rounds)}. Ritm pentru ${rounds(it)}." }
            ?: "Ține-ți ritmul."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Continuă." else ". Ține ritmul."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} în total")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} și ${seconds(s)}"
        }
    }

    private fun recordingSoon(n: Int): String =
        if (n == 1) "Înregistrare într-o secundă" else "Înregistrare în ${seconds(n)}"

    private fun rounds(n: Int) = noun(n, "o rundă", "două runde", "runde")
    private fun reps(n: Int) = noun(n, "o repetare", "două repetări", "repetări")
    private fun minutes(n: Int) = noun(n, "un minut", "două minute", "minute")
    private fun seconds(n: Int) = noun(n, "o secundă", "două secunde", "secunde")

    private fun noun(n: Int, one: String, two: String, plural: String): String = when {
        n == 1 -> one
        n == 2 -> two
        Plurals.romanian(n) == Plural.FEW -> "$n $plural"
        else -> "$n de $plural"
    }
}
