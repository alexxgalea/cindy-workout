package com.cindy.tracker

/**
 * The voice in Russian.
 *
 * Register: the informal "ты", in short imperatives. Plurals: one, few and many (1 раунд, 2–4
 * раунда, 5 раундов, but 11 раундов and 21 раунд). 1 and 2 are written out for the feminine nouns
 * ("одна минута", "две минуты") and 1 for the neuter "одно повторение", because a voice does not
 * reliably agree the numeral's gender with the noun after a digit. Confirmations and results
 * avoid the past tense of the athlete ("побил" or "побила"): the benchmark line says the result is
 * better, which is true whoever is listening. Sentences end on a word, never on a number.
 *
 * Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
 * for the engine to agree. That is the known gap, and the one to listen for on a real voice.
 *
 * Written without a native speaker's review; the lines are short so that they can be read that way.
 */
object PhrasebookRu : Phrasebook {

    override val tag = "ru"

    override fun say(line: VoiceLine): String = when (line) {
        is VoiceLine.Count -> "${line.reps}"
        is VoiceLine.Movement -> when (line.exercise) {
            Exercise.PULLUP -> "подтягивания"
            Exercise.PUSHUP -> "отжимания"
            Exercise.SQUAT -> "приседания"
        }
        is VoiceLine.RoundDone -> "Раунд ${line.round}, время ${duration(line.splitMs)}"
        VoiceLine.PhoneMoved -> "Телефон сдвинулся. Проверь кадр."
        VoiceLine.SetUp -> "Встань в кадр и сделай два медленных подтягивания"
        is VoiceLine.Go ->
            if (line.calibrated) "Калибровка завершена. Старт." else "Старт. Подтягивания"
        VoiceLine.Resume -> "Продолжаем"
        is VoiceLine.Finished -> if (line.early) "Остановлено." else "Время."
        is VoiceLine.Score -> score(line.rounds, line.totalReps)
        is VoiceLine.Averaging -> "В среднем ${duration(line.roundMs)} на раунд"
        is VoiceLine.BeatBenchmark -> "Результат лучше, чем у ${line.name}"
        VoiceLine.Ready -> "Готово"
        is VoiceLine.Fault -> Hint.of(line.hint)?.let { hint(it) } ?: "Проверь своё положение"
        is VoiceLine.Clock -> clock(line)
        VoiceLine.Sample -> "Три. Четыре. Пять. Отжимания."
        VoiceLine.VolumeCheck -> "Три"
        is VoiceLine.RecordingSoon -> "Запись через ${secondsAfterCherez(line.seconds)}"
        VoiceLine.RecordingStarted -> "Идёт запись"
        VoiceLine.RecordingFailed -> "Запись не удалась"
        VoiceLine.AdaptiveHeelsFlat -> "Адаптивная Cindy включена для приседаний с пятками на полу."
    }

    private fun hint(hint: Hint): String = when (hint) {
        Hint.STEP_INTO_FRAME -> "Встань в кадр"
        Hint.FINISH_SETUP_FIRST -> "Сначала закончи подготовку"
        Hint.TRACKING -> "Ищу тебя"
        Hint.HANG_FROM_BAR -> "Повисни на перекладине"
        Hint.HANG_VERTICALLY -> "Повисни на перекладине вертикально"
        Hint.GET_ON_BAR -> "Возьмись за перекладину"
        Hint.SHOW_BOTH_HANDS -> "Покажи обе руки"
        Hint.SHOW_YOUR_HEAD -> "Покажи голову"
        Hint.ARMS_OUT_OF_FRAME -> "Руки вышли из кадра"
        Hint.GET_HEAD_OVER_BAR -> "Подними голову выше перекладины"
        Hint.RETURN_TO_DEAD_HANG -> "Вернись в вис на прямых руках"
        Hint.LOWER_ALL_THE_WAY -> "Опустись до конца"
        Hint.GET_SET_ON_FLOOR -> "Прими положение на полу"
        Hint.GET_ON_FLOOR -> "Ляг на пол"
        Hint.STAND_UP_TO_START -> "Встань, чтобы начать"
        Hint.SHOW_YOUR_LEGS -> "Покажи ноги камере"
        Hint.DRIVE_UP -> "Вытолкни себя вверх"
        Hint.GO_DOWN -> "Опустись"
        Hint.LOSING_YOU -> "Теряю тебя из виду. Больше света поможет."
        Hint.TOO_DARK -> "Слишком темно для счёта. Нажми кнопку плюс один."
        Hint.CANT_SEE_YOU -> "Не вижу тебя. Нажми кнопку плюс один."
    }

    private fun clock(line: VoiceLine.Clock): String = when (line.mark) {
        ClockMark.TEN_SECONDS_LEFT -> "Десять секунд. Выложись полностью."
        ClockMark.ONE_MINUTE_LEFT -> "Осталась минута. Раундов: ${line.rounds}, закончи текущий."
        ClockMark.TWO_MINUTES_LEFT -> "Две минуты. " + push(line.rounds, line.totalReps)
        ClockMark.FIVE_MINUTES_LEFT -> "Осталось пять минут. " + pace(line)
        ClockMark.HALFWAY -> "Половина времени. " + pace(line)
        ClockMark.FIVE_MINUTES_IN -> "Прошло пять минут. " + pace(line)
    }

    private fun pace(line: VoiceLine.Clock): String =
        line.projectedRounds?.let { "Раундов: ${line.rounds}, темп на ${rounds(it)}." }
            ?: "Держи свой темп."

    private fun push(rounds: Int, totalReps: Int): String =
        score(rounds, totalReps) + if (rounds < 1) ". Продолжай." else ". Держи темп."

    private fun score(rounds: Int, totalReps: Int): String =
        (if (rounds < 1) reps(totalReps) else "${rounds(rounds)}, всего ${reps(totalReps)}")
            .capitalised()

    private fun duration(ms: Long): String {
        val (m, s) = minutesAndSeconds(ms)
        return when {
            m == 0 -> seconds(s)
            s == 0 -> minutes(m)
            else -> "${minutes(m)} и ${seconds(s)}"
        }
    }

    private fun rounds(n: Int) = when (Plurals.russian(n)) {
        Plural.ONE -> "$n раунд"
        Plural.FEW -> "$n раунда"
        else -> "$n раундов"
    }

    private fun reps(n: Int) = when (Plurals.russian(n)) {
        Plural.ONE -> if (n == 1) "одно повторение" else "$n повторение"
        Plural.FEW -> "$n повторения"
        else -> "$n повторений"
    }

    private fun minutes(n: Int) = when (Plurals.russian(n)) {
        Plural.ONE -> if (n == 1) "одна минута" else "$n минута"
        Plural.FEW -> if (n == 2) "две минуты" else "$n минуты"
        else -> "$n минут"
    }

    private fun seconds(n: Int) = when (Plurals.russian(n)) {
        Plural.ONE -> if (n == 1) "одна секунда" else "$n секунда"
        Plural.FEW -> if (n == 2) "две секунды" else "$n секунды"
        else -> "$n секунд"
    }

    /** After "через" the feminine singular is accusative: "через одну секунду". */
    private fun secondsAfterCherez(n: Int) = when {
        n == 1 -> "одну секунду"
        Plurals.russian(n) == Plural.ONE -> "$n секунду"
        else -> seconds(n)
    }
}
