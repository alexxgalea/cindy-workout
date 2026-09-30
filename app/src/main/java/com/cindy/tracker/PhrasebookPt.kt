package com.cindy.tracker

/**
 * The voice in Brazilian Portuguese.
 *
 * Register: "você", in short imperatives. Plurals: nought and one are both singular, as they are
 * in Brazilian Portuguese ("0 repetição"). 1 and 2 are written out for the feminine nouns ("uma
 * rodada", "duas rodadas"), because a voice can read a bare "2 rodadas" as "dois rodadas". The
 * minutes and seconds are masculine and need no help. Confirmations avoid words that change with
 * the athlete's gender ("pronto", "pronta"). Sentences end on a word, never on a number.
 *
 * Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
 * for the engine to agree. That is the known gap, and the one to listen for on a real voice.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookPt : Phrasebook {

    override val tag = "pt"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "barras"
            Exercise.PUSHUP -> "flexões"
            Exercise.SQUAT -> "agachamentos"
        }
        is VoiceLine.RoundDone -> "Rodada ${line.round} em ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "O celular se mexeu. Confira o enquadramento."
        VoiceLine.SetUp -> "Entre no enquadramento e faça duas barras lentas"
        is VoiceLine.Go -> if (line.calibrated) "Calibrado. Vai." else "Vai. Barras"
        VoiceLine.Resume -> "Retomando"
        is VoiceLine.Finished -> if (line.early) "Interrompido." else "Tempo."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "Média de ${duration(line.roundMs)} por rodada"
        is VoiceLine.BeatBenchmark -> "Você superou ${line.name}"
        VoiceLine.Ready -> "Tudo certo"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Confira a sua posição"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Três. Quatro. Cinco. Flexões."
        VoiceLine.VolumeCheck -> "Três"
        is VoiceLine.RecordingSoon -> "Gravando em ${seconds(line.seconds)}"
        VoiceLine.RecordingStarted -> "Gravando"
        VoiceLine.RecordingFailed -> "Falha na gravação"
        VoiceLine.AdaptiveHeelsFlat -> "Cindy adaptada ativada para agachamentos com os calcanhares no chão."
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Entre no enquadramento"
        Hint.FINISH_SETUP_FIRST -> "Termine primeiro a preparação"
        Hint.TRACKING -> "Localizando você"
        Hint.HANG_FROM_BAR -> "Pendure-se na barra"
        Hint.HANG_VERTICALLY -> "Pendure-se na barra na vertical"
        Hint.GET_ON_BAR -> "Segure a barra"
        Hint.SHOW_BOTH_HANDS -> "Mostre as duas mãos"
        Hint.SHOW_YOUR_HEAD -> "Mostre a cabeça"
        Hint.ARMS_OUT_OF_FRAME -> "Seus braços estão fora do enquadramento"
        Hint.GET_HEAD_OVER_BAR -> "Passe a cabeça acima da barra"
        Hint.RETURN_TO_DEAD_HANG -> "Volte a se pendurar com os braços esticados"
        Hint.LOWER_ALL_THE_WAY -> "Desça até o fim"
        Hint.GET_SET_ON_FLOOR -> "Posicione-se no chão"
        Hint.GET_ON_FLOOR -> "Vá para o chão"
        Hint.STAND_UP_TO_START -> "Fique de pé para começar"
        Hint.SHOW_YOUR_LEGS -> "Mostre as pernas para a câmera"
        Hint.DRIVE_UP -> "Empurre para cima"
        Hint.GO_DOWN -> "Desça"
        Hint.LOSING_YOU -> "Estou perdendo você de vista. Mais luz ajuda."
        Hint.TOO_DARK -> "Escuro demais para contar. Toque no botão mais um."
        Hint.CANT_SEE_YOU -> "Não vejo você. Toque no botão mais um."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Dez segundos. Dê tudo o que tem."
        ClockMark.ONE_MINUTE_LEFT ->
            "Falta um minuto. Você tem ${rounds(line.rounds)}. Termine a que está fazendo."
        ClockMark.TWO_MINUTES_LEFT -> "Dois minutos. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Faltam cinco minutos. " + pace(line)
        ClockMark.HALFWAY -> "Metade do tempo. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Cinco minutos. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Você tem ${rounds(line.rounds)}. Ritmo para ${rounds(it)}." }
            ?: "Mantenha o seu ritmo."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Continue." else ". Mantenha o ritmo."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, ${reps(totalReps)} no total")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} e ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = feminine(n, "rodada", "rodadas")
    private fun reps(n: Int) = feminine(n, "repetição", "repetições")
    private fun minutes(n: Int) = masculine(n, "minuto", "minutos")
    private fun seconds(n: Int) = masculine(n, "segundo", "segundos")

    private fun feminine(n: Int, singular: String, plural: String): String = when {
        n == 1 -> "uma $singular"
        n == 2 -> "duas $plural"
        Plurals.zeroOrOne(n) == Plural.ONE -> "$n $singular"
        else -> "$n $plural"
    }

    private fun masculine(n: Int, singular: String, plural: String): String = when {
        n == 1 -> "um $singular"
        Plurals.zeroOrOne(n) == Plural.ONE -> "$n $singular"
        else -> "$n $plural"
    }
}
