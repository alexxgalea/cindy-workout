package com.cindy.tracker

/**
 * The voice in Spanish.
 *
 * Register: the informal "tú", in short imperatives, as a coach says them. Plurals: one and other.
 * A voice reads a bare "1 ronda" as "uno ronda", so 1 is written out ("una ronda", "un minuto")
 * and everything else is left as a digit. Sentences end on a word, never on a number, because a
 * digit before a full stop is read by some engines as an ordinal.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookEs : Phrasebook {

    override val tag = "es"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "dominadas"
            Exercise.PUSHUP -> "flexiones"
            Exercise.SQUAT -> "sentadillas"
        }
        is VoiceLine.RoundDone -> "Ronda ${line.round} en ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "El teléfono se movió. Revisa el encuadre."
        VoiceLine.SetUp -> "Colócate en el encuadre y haz dos dominadas lentas"
        is VoiceLine.Go -> if (line.calibrated) "Calibrado. Ya." else "Ya. Dominadas"
        VoiceLine.Resume -> "Seguimos"
        is VoiceLine.Finished -> if (line.early) "Detenido." else "Tiempo."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "De media, ${duration(line.roundMs)} por ronda"
        is VoiceLine.BeatBenchmark -> "Superaste a ${line.name}"
        VoiceLine.Ready -> "Todo listo"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Revisa tu posición"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Tres. Cuatro. Cinco. Flexiones."
        VoiceLine.VolumeCheck -> "Tres"
        is VoiceLine.RecordingSoon -> "Grabando en ${seconds(line.seconds)}"
        VoiceLine.RecordingStarted -> "Grabando"
        VoiceLine.RecordingFailed -> "Falló la grabación"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Entra en el encuadre"
        Hint.FINISH_SETUP_FIRST -> "Termina primero la preparación"
        Hint.TRACKING -> "Localizándote"
        Hint.HANG_FROM_BAR -> "Cuélgate de la barra"
        Hint.HANG_VERTICALLY -> "Cuélgate de la barra en vertical"
        Hint.GET_ON_BAR -> "Agárrate a la barra"
        Hint.SHOW_BOTH_HANDS -> "Muestra las dos manos"
        Hint.SHOW_YOUR_HEAD -> "Muestra la cabeza"
        Hint.ARMS_OUT_OF_FRAME -> "Tus brazos quedan fuera del encuadre"
        Hint.GET_HEAD_OVER_BAR -> "Sube la cabeza por encima de la barra"
        Hint.RETURN_TO_DEAD_HANG -> "Vuelve a colgarte con los brazos estirados"
        Hint.LOWER_ALL_THE_WAY -> "Baja del todo"
        Hint.GET_SET_ON_FLOOR -> "Colócate en el suelo"
        Hint.GET_ON_FLOOR -> "Ponte en el suelo"
        Hint.STAND_UP_TO_START -> "Ponte de pie para empezar"
        Hint.SHOW_YOUR_LEGS -> "Muestra las piernas a la cámara"
        Hint.DRIVE_UP -> "Empuja hacia arriba"
        Hint.GO_DOWN -> "Baja"
        Hint.LOSING_YOU -> "Te pierdo de vista. Ayuda más luz."
        Hint.TOO_DARK -> "Demasiado oscuro para contar. Pulsa el botón más uno."
        Hint.CANT_SEE_YOU -> "No te veo. Pulsa el botón más uno."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Diez segundos. Todo lo que tengas."
        ClockMark.ONE_MINUTE_LEFT ->
            "Queda un minuto. Llevas ${rounds(line.rounds)}. Termina la que estás haciendo."
        ClockMark.TWO_MINUTES_LEFT -> "Dos minutos. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Quedan cinco minutos. " + pace(line)
        ClockMark.HALFWAY -> "A mitad de camino. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Cinco minutos. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Llevas ${rounds(line.rounds)}. Ritmo para ${rounds(it)}." }
            ?: "Mantén tu ritmo."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Sigue así." else ". Mantén el ritmo."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} en total")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} y ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = noun(n, "una ronda", "rondas")
    private fun reps(n: Int) = noun(n, "una repetición", "repeticiones")
    private fun minutes(n: Int) = noun(n, "un minuto", "minutos")
    private fun seconds(n: Int) = noun(n, "un segundo", "segundos")

    private fun noun(n: Int, one: String, other: String): String =
        if (Plurals.oneOther(n) == Plural.ONE) one else "$n $other"
}
