package com.cindy.tracker

/**
 * The voice in Polish.
 *
 * Register: the informal imperative. Plurals: one, few and many (1 runda, 2–4 rundy, 5 rund, but
 * 12 rund and 22 rundy). 1 and 2 are written out for the feminine nouns ("jedna runda", "dwie
 * rundy"), because a voice reads a bare "2 rundy" as "dwa rundy"; the neuter "powtórzenie" takes
 * "jedno" and needs nothing for 2.
 *
 * A count inside a sentence would need the case of the verb before it, and the feminine singular
 * changes shape in the accusative ("rundę"), so counted phrases are kept to places that ask for
 * the nominative: a standalone score, a duration after "czas", and a label such as "Ukończone
 * rundy: 6". The one accusative that cannot be avoided ("za jedną sekundę", "na jedną rundę") is
 * written out. Sentences end on a word, never on a number: Polish engines read "12." as an ordinal.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookPl : Phrasebook {

    override val tag = "pl"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "podciągnięcia"
            Exercise.PUSHUP -> "pompki"
            Exercise.SQUAT -> "przysiady"
        }
        is VoiceLine.RoundDone -> "Runda ${line.round}, czas ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Telefon się przesunął. Sprawdź kadr."
        VoiceLine.SetUp -> "Wejdź w kadr i zrób dwa powolne podciągnięcia"
        is VoiceLine.Go -> if (line.calibrated) "Skalibrowano. Start." else "Start. Podciągnięcia"
        VoiceLine.Resume -> "Wznawiamy"
        is VoiceLine.Finished -> if (line.early) "Zatrzymano." else "Koniec czasu."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Średnio ${duration(line.roundMs)} na rundę"
        is VoiceLine.BeatBenchmark -> "Wynik lepszy niż ${line.name}"
        VoiceLine.Ready -> "Gotowe"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Sprawdź swoją pozycję"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Trzy. Cztery. Pięć. Pompki."
        VoiceLine.VolumeCheck -> "Trzy"
        is VoiceLine.RecordingSoon -> "Nagrywanie za ${secondsAfterZa(line.seconds)}"
        VoiceLine.RecordingStarted -> "Nagrywanie rozpoczęte"
        VoiceLine.RecordingFailed -> "Nagrywanie nie powiodło się"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Wejdź w kadr"
        Hint.FINISH_SETUP_FIRST -> "Najpierw dokończ przygotowanie"
        Hint.TRACKING -> "Szukam cię"
        Hint.HANG_FROM_BAR -> "Zwiś na drążku"
        Hint.HANG_VERTICALLY -> "Zwiś pionowo na drążku"
        Hint.GET_ON_BAR -> "Chwyć drążek"
        Hint.SHOW_BOTH_HANDS -> "Pokaż obie dłonie"
        Hint.SHOW_YOUR_HEAD -> "Pokaż głowę"
        Hint.ARMS_OUT_OF_FRAME -> "Ramiona są poza kadrem"
        Hint.GET_HEAD_OVER_BAR -> "Podnieś głowę nad drążek"
        Hint.RETURN_TO_DEAD_HANG -> "Wróć do zwisu na wyprostowanych rękach"
        Hint.LOWER_ALL_THE_WAY -> "Opuść się do końca"
        Hint.GET_SET_ON_FLOOR -> "Przyjmij pozycję na podłodze"
        Hint.GET_ON_FLOOR -> "Połóż się na podłodze"
        Hint.STAND_UP_TO_START -> "Wstań, żeby zacząć"
        Hint.SHOW_YOUR_LEGS -> "Pokaż nogi kamerze"
        Hint.DRIVE_UP -> "Wypchnij się w górę"
        Hint.GO_DOWN -> "Opuść się"
        Hint.LOSING_YOU -> "Tracę cię z oczu. Więcej światła pomoże."
        Hint.TOO_DARK -> "Za ciemno, żeby liczyć. Dotknij plus jeden."
        Hint.CANT_SEE_YOU -> "Nie widzę cię. Dotknij plus jeden."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Dziesięć sekund. Daj z siebie wszystko."
        ClockMark.ONE_MINUTE_LEFT ->
            "Została minuta. Ukończone rundy: ${line.rounds}, dokończ bieżącą."
        ClockMark.TWO_MINUTES_LEFT -> "Dwie minuty. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Zostało pięć minut. " + pace(line)
        ClockMark.HALFWAY -> "Połowa czasu. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Pięć minut za nami. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let {
            "Ukończone rundy: ${line.rounds}, tempo na ${roundsAfterNa(it)}."
        } ?: "Utrzymaj swoje tempo."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Dalej." else ". Utrzymaj tempo."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, łącznie ${reps(totalReps)}")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} i ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = when (Plurals.polish(n)) {
        Plural.ONE -> "jedna runda"
        Plural.FEW -> if (n == 2) "dwie rundy" else "$n rundy"
        else -> "$n rund"
    }

    private fun reps(n: Int) = when (Plurals.polish(n)) {
        Plural.ONE -> "jedno powtórzenie"
        Plural.FEW -> "$n powtórzenia"
        else -> "$n powtórzeń"
    }

    private fun minutes(n: Int) = when (Plurals.polish(n)) {
        Plural.ONE -> "jedna minuta"
        Plural.FEW -> if (n == 2) "dwie minuty" else "$n minuty"
        else -> "$n minut"
    }

    private fun seconds(n: Int) = when (Plurals.polish(n)) {
        Plural.ONE -> "jedna sekunda"
        Plural.FEW -> if (n == 2) "dwie sekundy" else "$n sekundy"
        else -> "$n sekund"
    }

    /** After "za" the feminine singular is accusative: "za jedną sekundę". */
    private fun secondsAfterZa(n: Int) = if (Plurals.polish(n) == Plural.ONE) "jedną sekundę" else seconds(n)

    /** After "na" the feminine singular is accusative: "na jedną rundę". */
    private fun roundsAfterNa(n: Int) = if (Plurals.polish(n) == Plural.ONE) "jedną rundę" else rounds(n)
}
