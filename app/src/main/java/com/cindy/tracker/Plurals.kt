package com.cindy.tracker

/** The plural forms the voice's languages use, named as the Unicode CLDR rules name them. */
enum class Plural { ONE, FEW, MANY, OTHER }

/**
 * Which form of a noun goes with a count, for each rule family the phrasebooks need.
 *
 * "2 round" is a mistake in English and only a slightly worse one in Spanish, but in Polish,
 * Romanian and Russian the form changes at 2, at 5, at 12 and again at 22, and a score is read out
 * loud to someone who is out of breath: "5 rundy" instead of "5 rund" is noticed. So each
 * language names the rule it follows rather than approximating with "one or more than one".
 *
 * These are the CLDR cardinal rules restricted to whole numbers, which is all a count of rounds,
 * repetitions, minutes or seconds ever is. Every argument is a count and never negative.
 */
object Plurals {

    /** English, Spanish, German, Italian, Dutch: exactly one is singular. */
    fun oneOther(n: Int): Plural = if (n == 1) Plural.ONE else Plural.OTHER

    /** French and Brazilian Portuguese: nought and one are both singular ("0 tour"). */
    fun zeroOrOne(n: Int): Plural = if (n == 0 || n == 1) Plural.ONE else Plural.OTHER

    /**
     * Polish: one; then a "few" form for counts ending 2–4 except the teens, and a "many" form
     * for everything else (0, 5–21, 25–31 …), so 22 is "few" and 12 is not.
     */
    fun polish(n: Int): Plural = when {
        n == 1 -> Plural.ONE
        n % 10 in 2..4 && n % 100 !in 12..14 -> Plural.FEW
        else -> Plural.MANY
    }

    /**
     * Romanian: one; "few" for 0 and for anything ending 01–19 (so 2 to 19, and 101 to 119); and
     * "other" from 20, which is also the form that takes "de" ("20 de runde", "120 de runde").
     */
    fun romanian(n: Int): Plural = when {
        n == 1 -> Plural.ONE
        n == 0 || n % 100 in 1..19 -> Plural.FEW
        else -> Plural.OTHER
    }

    /**
     * Russian: "one" for counts ending 1 except 11, "few" for 2–4 except the teens, "many" for
     * the rest. 21 is singular again, and 111 is not.
     */
    fun russian(n: Int): Plural = when {
        n % 10 == 1 && n % 100 != 11 -> Plural.ONE
        n % 10 in 2..4 && n % 100 !in 12..14 -> Plural.FEW
        else -> Plural.MANY
    }
}
