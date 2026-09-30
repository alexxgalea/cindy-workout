package com.cindy.tracker

/**
 * The words for one language: every [VoiceLine], as a sentence a text-to-speech voice can say.
 *
 * One implementation per language, each an exhaustive `when` over [VoiceLine] with no `else`, so a
 * language that is missing a line is a compile error rather than a silent gap in the middle of a
 * workout. Kept free of Android types, which is what makes the grammar — plurals, agreement, what
 * a voice does to "3." — something a test can pin.
 *
 * The English phrasebook, [PhrasebookEn], is the reference: it says what the app has always said,
 * and the others are its translations.
 */
interface Phrasebook {

    /** The language this speaks for, as a lower-case tag such as `en` or `es`. */
    val tag: String

    /** The words for [line]. Never blank: a voice handed an empty utterance says nothing at all. */
    fun say(line: VoiceLine): String
}

/**
 * The whole minutes and the seconds left over in [ms], dropping any part of a second.
 *
 * Shared because every language wants the same split and only the words around it differ; the
 * dropped fraction matches the English phrasebook, which has always truncated rather than rounded.
 */
internal fun minutesAndSeconds(ms: Long): Pair<Int, Int> {
    val total = ms / 1000L
    return (total / 60).toInt() to (total % 60).toInt()
}
