package com.cindy.tracker

/**
 * The voice in German.
 *
 * Register: the informal "du", in short imperatives. Plurals: one and other. 1 is written out
 * ("eine Runde"), because a voice does not always agree the article with the noun after a digit.
 * The time of a round follows the word "Zeit" rather than "in", since "in" would put the count in
 * the dative ("in einer Minute") where the average wants the nominative ("eine Minute"). Sentences
 * end on a word, never on a number: German engines read "12." as "zwölfte".
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookDe : Phrasebook {

    override val tag = "de"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "Klimmzüge"
            Exercise.PUSHUP -> "Liegestütze"
            Exercise.SQUAT -> "Kniebeugen"
        }
        is VoiceLine.RoundDone -> "Runde ${line.round}, Zeit ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Das Handy hat sich bewegt. Prüfe den Bildausschnitt."
        VoiceLine.SetUp -> "Geh ins Bild und mach dann zwei langsame Klimmzüge"
        is VoiceLine.Go -> if (line.calibrated) "Kalibriert. Los." else "Los. Klimmzüge"
        VoiceLine.Resume -> "Weiter"
        is VoiceLine.Finished -> if (line.early) "Gestoppt." else "Zeit."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Im Schnitt ${duration(line.roundMs)} pro Runde"
        is VoiceLine.BeatBenchmark -> "Du hast ${line.name} geschlagen"
        VoiceLine.Ready -> "Bereit"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Prüfe deine Position"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Drei. Vier. Fünf. Liegestütze."
        VoiceLine.VolumeCheck -> "Drei"
        is VoiceLine.RecordingSoon -> "Aufnahme in ${secondsAfterIn(line.seconds)}"
        VoiceLine.RecordingStarted -> "Aufnahme läuft"
        VoiceLine.RecordingFailed -> "Aufnahme fehlgeschlagen"
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Geh ins Bild"
        Hint.FINISH_SETUP_FIRST -> "Schließe zuerst die Vorbereitung ab"
        Hint.TRACKING -> "Ich suche dich"
        Hint.HANG_FROM_BAR -> "Häng dich an die Stange"
        Hint.HANG_VERTICALLY -> "Häng dich senkrecht an die Stange"
        Hint.GET_ON_BAR -> "Greif die Stange"
        Hint.SHOW_BOTH_HANDS -> "Zeig beide Hände"
        Hint.SHOW_YOUR_HEAD -> "Zeig deinen Kopf"
        Hint.ARMS_OUT_OF_FRAME -> "Deine Arme sind außerhalb des Bildes"
        Hint.GET_HEAD_OVER_BAR -> "Bring den Kopf über die Stange"
        Hint.RETURN_TO_DEAD_HANG -> "Häng dich wieder mit gestreckten Armen an die Stange"
        Hint.LOWER_ALL_THE_WAY -> "Geh ganz nach unten"
        Hint.GET_SET_ON_FLOOR -> "Geh in Position auf dem Boden"
        Hint.GET_ON_FLOOR -> "Geh auf den Boden"
        Hint.STAND_UP_TO_START -> "Steh zum Start auf"
        Hint.SHOW_YOUR_LEGS -> "Zeig der Kamera deine Beine"
        Hint.DRIVE_UP -> "Drück dich hoch"
        Hint.GO_DOWN -> "Geh runter"
        Hint.LOSING_YOU -> "Ich verliere dich aus dem Blick. Mehr Licht hilft."
        Hint.TOO_DARK -> "Zu dunkel zum Zählen. Tippe auf plus eins."
        Hint.CANT_SEE_YOU -> "Ich sehe dich nicht. Tippe auf plus eins."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Zehn Sekunden. Gib alles."
        ClockMark.ONE_MINUTE_LEFT ->
            "Noch eine Minute. ${rounds(line.rounds).capitalised()} geschafft. Beende die laufende Runde."
        ClockMark.TWO_MINUTES_LEFT -> "Zwei Minuten. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Noch fünf Minuten. " + pace(line)
        ClockMark.HALFWAY -> "Halbzeit. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Fünf Minuten sind um. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let {
            "${rounds(line.rounds).capitalised()} geschafft. Tempo für ${rounds(it)}."
        } ?: "Halte dein Tempo."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Weiter so." else ". Halte das Tempo."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} insgesamt")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} und ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = noun(n, "eine Runde", "Runden")
    private fun reps(n: Int) = noun(n, "eine Wiederholung", "Wiederholungen")
    private fun minutes(n: Int) = noun(n, "eine Minute", "Minuten")
    private fun seconds(n: Int) = noun(n, "eine Sekunde", "Sekunden")

    /** After "in" the singular is dative: "in einer Sekunde". */
    private fun secondsAfterIn(n: Int) = if (n == 1) "einer Sekunde" else seconds(n)

    private fun noun(n: Int, one: String, other: String): String =
        if (Plurals.oneOther(n) == Plural.ONE) one else "$n $other"
}
