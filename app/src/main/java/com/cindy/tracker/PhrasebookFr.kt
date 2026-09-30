package com.cindy.tracker

/**
 * The voice in French.
 *
 * Register: the informal "tu", in short imperatives. Plurals: nought and one are both singular
 * ("0 tour", "1 tour"), which is French and not a slip. 1 is written out ("un tour", "une
 * répétition") because a voice does not always agree the article with the noun that follows a digit.
 * Sentences end on a word, never on a number, because a digit before a full stop is read by some
 * engines as an ordinal.
 *
 * Counts other than 1 are left as digits for the engine to agree with the noun that follows.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookFr : Phrasebook {

    override val tag = "fr"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "tractions"
            Exercise.PUSHUP -> "pompes"
            Exercise.SQUAT -> "squats"
        }
        is VoiceLine.RoundDone -> "Tour ${line.round} en ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Le téléphone a bougé. Vérifie le cadrage."
        VoiceLine.SetUp -> "Place-toi dans le cadre, puis fais deux tractions lentes"
        is VoiceLine.Go -> if (line.calibrated) "Calibré. C'est parti." else "C'est parti. Tractions"
        VoiceLine.Resume -> "On reprend"
        is VoiceLine.Finished -> if (line.early) "Arrêté." else "Temps."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "En moyenne, ${duration(line.roundMs)} par tour"
        is VoiceLine.BeatBenchmark -> "Tu as battu ${line.name}"
        VoiceLine.Ready -> "C'est bon"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Vérifie ta position"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Trois. Quatre. Cinq. Pompes."
        VoiceLine.VolumeCheck -> "Trois"
        is VoiceLine.RecordingSoon -> "Enregistrement dans ${seconds(line.seconds)}"
        VoiceLine.RecordingStarted -> "Enregistrement en cours"
        VoiceLine.RecordingFailed -> "L'enregistrement a échoué"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Place-toi dans le cadre"
        Hint.FINISH_SETUP_FIRST -> "Termine d'abord la préparation"
        Hint.TRACKING -> "Recherche en cours"
        Hint.HANG_FROM_BAR -> "Suspends-toi à la barre"
        Hint.HANG_VERTICALLY -> "Suspends-toi à la barre, à la verticale"
        Hint.GET_ON_BAR -> "Attrape la barre"
        Hint.SHOW_BOTH_HANDS -> "Montre les deux mains"
        Hint.SHOW_YOUR_HEAD -> "Montre ta tête"
        Hint.ARMS_OUT_OF_FRAME -> "Tes bras sortent du cadre"
        Hint.GET_HEAD_OVER_BAR -> "Passe la tête au-dessus de la barre"
        Hint.RETURN_TO_DEAD_HANG -> "Reviens en suspension, bras tendus"
        Hint.LOWER_ALL_THE_WAY -> "Descends complètement"
        Hint.GET_SET_ON_FLOOR -> "Mets-toi en position au sol"
        Hint.GET_ON_FLOOR -> "Mets-toi au sol"
        Hint.STAND_UP_TO_START -> "Lève-toi pour commencer"
        Hint.SHOW_YOUR_LEGS -> "Montre tes jambes à la caméra"
        Hint.DRIVE_UP -> "Pousse vers le haut"
        Hint.GO_DOWN -> "Descends"
        Hint.LOSING_YOU -> "Je te perds de vue. Plus de lumière aiderait."
        Hint.TOO_DARK -> "Trop sombre pour compter. Touche le bouton plus un."
        Hint.CANT_SEE_YOU -> "Je ne te vois pas. Touche le bouton plus un."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Dix secondes. Donne tout."
        ClockMark.ONE_MINUTE_LEFT ->
            "Il reste une minute. Tu en es à ${rounds(line.rounds)}. Termine celui en cours."
        ClockMark.TWO_MINUTES_LEFT -> "Deux minutes. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Il reste cinq minutes. " + pace(line)
        ClockMark.HALFWAY -> "À mi-parcours. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Cinq minutes. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Tu en es à ${rounds(line.rounds)}. Rythme pour ${rounds(it)}." }
            ?: "Garde ton rythme."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Continue." else ". Garde le rythme."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} au total")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} et ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = noun(n, "un tour", "tour", "tours")
    private fun reps(n: Int) = noun(n, "une répétition", "répétition", "répétitions")
    private fun minutes(n: Int) = noun(n, "une minute", "minute", "minutes")
    private fun seconds(n: Int) = noun(n, "une seconde", "seconde", "secondes")

    private fun noun(n: Int, one: String, singular: String, plural: String): String = when {
        n == 1 -> one
        Plurals.zeroOrOne(n) == Plural.ONE -> "$n $singular"
        else -> "$n $plural"
    }
}
