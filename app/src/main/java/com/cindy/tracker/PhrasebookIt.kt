package com.cindy.tracker

/**
 * The voice in Italian.
 *
 * Register: the informal "tu", in short imperatives. Plurals: one and other. 1 is written out
 * ("un giro", "una ripetizione") because a voice does not always agree the article with the noun after a
 * digit. A round is a "giro", the word a circuit uses, rather than the English "round", which an
 * Italian voice pronounces in its own way. Confirmations avoid words that change with the
 * athlete's gender ("pronto", "pronta"). Sentences end on a word, never on a number.
 *
 * Counts other than 1 are left as digits for the engine to agree with the noun that follows.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookIt : Phrasebook {

    override val tag = "it"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "trazioni"
            Exercise.PUSHUP -> "flessioni"
            Exercise.SQUAT -> "squat"
        }
        is VoiceLine.RoundDone -> "Giro ${line.round} in ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Il telefono si è mosso. Controlla l'inquadratura."
        VoiceLine.SetUp -> "Mettiti nell'inquadratura, poi fai due trazioni lente"
        is VoiceLine.Go -> if (line.calibrated) "Calibrato. Via." else "Via. Trazioni"
        VoiceLine.Resume -> "Si riprende"
        is VoiceLine.Finished -> if (line.early) "Fermato." else "Tempo."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "In media ${duration(line.roundMs)} a giro"
        is VoiceLine.BeatBenchmark -> "Hai battuto ${line.name}"
        VoiceLine.Ready -> "Posizione ok"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Controlla la tua posizione"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Tre. Quattro. Cinque. Flessioni."
        VoiceLine.VolumeCheck -> "Tre"
        is VoiceLine.RecordingSoon -> "Registrazione tra ${seconds(line.seconds)}"
        VoiceLine.RecordingStarted -> "Registrazione in corso"
        VoiceLine.RecordingFailed -> "Registrazione non riuscita"
        VoiceLine.AdaptiveHeelsFlat -> "Cindy adattata attivata per gli squat con i talloni a terra."
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Entra nell'inquadratura"
        Hint.FINISH_SETUP_FIRST -> "Completa prima la preparazione"
        Hint.TRACKING -> "Ti sto cercando"
        Hint.HANG_FROM_BAR -> "Appenditi alla sbarra"
        Hint.HANG_VERTICALLY -> "Appenditi alla sbarra in verticale"
        Hint.GET_ON_BAR -> "Afferra la sbarra"
        Hint.SHOW_BOTH_HANDS -> "Mostra entrambe le mani"
        Hint.SHOW_YOUR_HEAD -> "Mostra la testa"
        Hint.ARMS_OUT_OF_FRAME -> "Le braccia sono fuori inquadratura"
        Hint.GET_HEAD_OVER_BAR -> "Porta la testa sopra la sbarra"
        Hint.RETURN_TO_DEAD_HANG -> "Torna appeso a braccia tese"
        Hint.LOWER_ALL_THE_WAY -> "Scendi fino in fondo"
        Hint.GET_SET_ON_FLOOR -> "Mettiti in posizione a terra"
        Hint.GET_ON_FLOOR -> "Mettiti a terra"
        Hint.STAND_UP_TO_START -> "Alzati per iniziare"
        Hint.SHOW_YOUR_LEGS -> "Mostra le gambe alla fotocamera"
        Hint.DRIVE_UP -> "Spingi verso l'alto"
        Hint.GO_DOWN -> "Scendi"
        Hint.LOSING_YOU -> "Ti perdo di vista. Serve più luce."
        Hint.TOO_DARK -> "Troppo buio per contare. Tocca il pulsante più uno."
        Hint.CANT_SEE_YOU -> "Non ti vedo. Tocca il pulsante più uno."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Dieci secondi. Dai tutto."
        ClockMark.ONE_MINUTE_LEFT ->
            "Manca un minuto. Sei a ${rounds(line.rounds)}. Finisci quello in corso."
        ClockMark.TWO_MINUTES_LEFT -> "Due minuti. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Mancano cinque minuti. " + pace(line)
        ClockMark.HALFWAY -> "Metà tempo. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Cinque minuti. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Sei a ${rounds(line.rounds)}. Ritmo da ${rounds(it)}." }
            ?: "Mantieni il tuo ritmo."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Continua così." else ". Mantieni il ritmo."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} in totale")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} e ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = noun(n, "un giro", "giri")
    private fun reps(n: Int) = noun(n, "una ripetizione", "ripetizioni")
    private fun minutes(n: Int) = noun(n, "un minuto", "minuti")
    private fun seconds(n: Int) = noun(n, "un secondo", "secondi")

    private fun noun(n: Int, one: String, other: String): String =
        if (Plurals.oneOther(n) == Plural.ONE) one else "$n $other"
}
