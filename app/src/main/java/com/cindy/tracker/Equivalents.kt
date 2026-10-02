package com.cindy.tracker

import java.util.Locale
import kotlin.math.roundToInt

/**
 * Everyday things a session's weight and energy are the size of, so "12,940 kg" and "312 kcal"
 * mean something at a glance.
 *
 * Weight is compared with animals, which is the point of the card. Energy is deliberately *not*
 * compared with food: "that was a doughnut" is the comparison that turns a workout into a debt,
 * and nobody asked for it. A cup of tea, a phone charge and an hour of lamp light are the same
 * kind of number with no moral attached.
 *
 * Both pickers take [canDraw] rather than assuming every emoji renders. The oldest phone this app
 * runs on (API 26) bundles an emoji font that predates some of these animals, and a hippo drawn as
 * an empty box is worse than a different animal.
 */
object Equivalents {

    data class Animal(val name: String, val plural: String, val kg: Int, val emoji: String)

    /** Heaviest first, so a larger session is matched by a larger animal when several would do. */
    val animals: List<Animal> = listOf(
        Animal("T. rex", "T. rexes", 8000, "🦖"),
        Animal("African elephant", "African elephants", 6000, "🐘"),
        Animal("white rhino", "white rhinos", 2300, "🦏"),
        Animal("hippo", "hippos", 1500, "🦛"),
        Animal("giraffe", "giraffes", 1200, "🦒"),
        Animal("cow", "cows", 700, "🐄"),
        Animal("horse", "horses", 500, "🐎"),
        Animal("brown bear", "brown bears", 300, "🐻"),
        Animal("gorilla", "gorillas", 160, "🦍"),
        Animal("giant panda", "giant pandas", 100, "🐼")
    )

    /** The fewest and most of an animal the card will ever claim. */
    private const val MIN_ANIMALS = 1.0
    private const val MAX_ANIMALS = 12.0

    /** A count worth meeting: below two it is barely a multiple, above nine it stops being countable. */
    private const val PREFERRED_MIN = 2.0
    private const val PREFERRED_MAX = 9.0

    /** [count] animals' worth, as [text] ("1.4 hippos", "9 hippos"). */
    data class AnimalMatch(val animal: Animal, val count: Double, val text: String)

    /**
     * An animal [kg] is a sensible number of, or null when none is (under one panda, over twelve
     * T. rexes, or none of the candidates can be drawn).
     *
     * Counts in [2, 9] are preferred. [rotation], the session's local calendar day number, picks
     * among them, so the athlete who trains every day does not meet the same hippo every time.
     * Rotating by the session's own day rather than the clock keeps a reopened session showing
     * what it showed the first time.
     */
    fun animalFor(kg: Double, rotation: Long, canDraw: (String) -> Boolean): AnimalMatch? {
        if (!(kg > 0.0)) return null
        val fits = animals
            .filter { canDraw(it.emoji) }
            .map { it to kg / it.kg }
            .filter { (_, count) -> count in MIN_ANIMALS..MAX_ANIMALS }
        val preferred = fits.filter { (_, count) -> count in PREFERRED_MIN..PREFERRED_MAX }
        val pool = preferred.ifEmpty { fits }
        if (pool.isEmpty()) return null
        val (animal, count) = pool[Math.floorMod(rotation, pool.size.toLong()).toInt()]
        return AnimalMatch(animal, count, countText(count, animal))
    }

    /**
     * "1.4 hippos" below three, "9 hippos" from three up.
     *
     * Decided on the rounded figure, so 2.96 reads "3 hippos" and not "3.0 hippos", and 1.04 reads
     * "1 hippo" and not "1.0 hippos".
     */
    fun countText(count: Double, animal: Animal): String {
        if (count < 3.0) {
            val tenths = String.format(Locale.US, "%.1f", count)
            if (tenths == "1.0") return "1 ${animal.name}"
            if (tenths != "3.0") return "$tenths ${animal.plural}"
        }
        val whole = count.roundToInt()
        return "$whole ${if (whole == 1) animal.name else animal.plural}"
    }

    /** "As heavy as 9 hippos.", "At least as heavy as 9 hippos." for a lower-bound score. */
    fun heavySentence(match: AnimalMatch, atLeast: Boolean): String =
        if (atLeast) "At least as heavy as ${match.text}." else "As heavy as ${match.text}."

    /** How many emoji to draw for [count], one to five. */
    fun emojiCount(count: Double): Int = count.roundToInt().coerceIn(1, MAX_EMOJI)

    /** Beyond this many the row is five and a "×9". */
    const val MAX_EMOJI = 5

    /**
     * A non-food thing some energy is the size of.
     *
     * [kcal] is the energy in one of it, [sentence] words a whole-number count of it, and [method]
     * says where the figure comes from, because the card is an estimate of an estimate and should
     * show its working.
     */
    data class EnergyReference(
        val emoji: String,
        val kcal: Double,
        val method: String,
        private val phrase: (Int) -> String
    ) {
        fun sentence(count: Int, atLeast: Boolean): String =
            (if (atLeast) "At least enough to " else "Enough to ") + phrase(count) + "."
    }

    val energyReferences: List<EnergyReference> = listOf(
        EnergyReference(
            "☕", 20.0,
            "A cup of tea is 250 ml of water heated from 20 °C to boiling, about 20 kcal."
        ) { n -> "boil water for $n ${if (n == 1) "cup" else "cups"} of tea" },
        EnergyReference(
            "🔋", 13.0,
            "A full phone charge is about 13 kcal (15 Wh)."
        ) { n -> "charge a phone fully ${if (n == 1) "once" else "$n times"}" },
        EnergyReference(
            "💡", 7.7,
            "An hour of a 9 W LED bulb is about 7.7 kcal."
        ) { n -> "run a 9 W LED bulb for $n ${if (n == 1) "hour" else "hours"}" }
    )

    private const val MIN_ENERGY_COUNT = 1
    private const val MAX_ENERGY_COUNT = 60

    data class EnergyMatch(val reference: EnergyReference, val count: Int)

    /**
     * A reference [kcal] is between 1 and 60 of, or null when none is (under about 7 kcal, or none
     * of the three can be drawn). Rotated like [animalFor], so consecutive sessions tend to
     * differ.
     */
    fun energyFor(kcal: Double, rotation: Long, canDraw: (String) -> Boolean): EnergyMatch? {
        if (!(kcal > 0.0)) return null
        val fits = energyReferences
            .filter { canDraw(it.emoji) }
            .map { it to (kcal / it.kcal).roundToInt() }
            .filter { (_, count) -> count in MIN_ENERGY_COUNT..MAX_ENERGY_COUNT }
        if (fits.isEmpty()) return null
        val (reference, count) = fits[Math.floorMod(rotation, fits.size.toLong()).toInt()]
        return EnergyMatch(reference, count)
    }
}
