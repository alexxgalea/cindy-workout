package com.cindy.tracker

/** One line of a Freestyle's set list: a set, or the Rest or Transition after it. */
data class FreestyleRow(
    val kind: Kind,
    val title: String,
    val detail: String,
    val length: String,
    /** For a SET row, its place in [Attempt.freestyleSets]; null for a Rest or Transition. */
    val setIndex: Int? = null
) {
    enum class Kind { SET, REST, TRANSITION }
}

/**
 * What a Freestyle session page says (spec #188), as words: one tile per movement, then every set
 * in order with the gap after each. Everything is read from the attempt's sets, so a relabelled
 * and re-derived attempt redraws with no other change.
 */
object FreestylePage {

    /** Reps, time in sets and number of sets per movement, in the order the movements are named. */
    fun tiles(a: Attempt): List<StatTile> {
        val derived = DerivedSets(a.freestyleSets, FreestyleSets.gapsBetween(a.freestyleSets))
        val totals = if (a.freestyleSets.isEmpty()) a.movementTotals else derived.totals
        return Exercise.entries.filter { (totals[it] ?: 0) > 0 }.map { movement ->
            val reps = totals.getValue(movement)
            val footnote = if (a.freestyleSets.isEmpty()) {
                "sets not recorded"
            } else {
                val n = derived.setCount(movement)
                "${formatDuration(derived.timeInSets(movement))} in sets · $n ${if (n == 1) "set" else "sets"}"
            }
            StatTile(movement.label, "$reps", footnote, "${movement.label}: $reps reps, $footnote")
        }
    }

    /** Sets and their gaps interleaved, in time order. Empty when no sets were filed. */
    fun rows(a: Attempt): List<FreestyleRow> {
        val gaps = FreestyleSets.gapsBetween(a.freestyleSets)
        return a.freestyleSets.flatMapIndexed { i, set ->
            val row = FreestyleRow(
                FreestyleRow.Kind.SET, set.movement.label,
                "${set.reps} ${if (set.reps == 1) "rep" else "reps"} · " +
                    "${formatDuration(set.startMs)}–${formatDuration(set.endMs)}" +
                    if (set.changedByAthlete) " · $CHANGED_BY_YOU" else "",
                formatDuration(set.lengthMs),
                setIndex = i
            )
            val gap = gaps.getOrNull(i)?.let {
                if (it.kind == GapKind.REST) {
                    FreestyleRow(FreestyleRow.Kind.REST, "Rest", "", formatDuration(it.lengthMs))
                } else {
                    FreestyleRow(FreestyleRow.Kind.TRANSITION, "Transition", "", formatDuration(it.lengthMs))
                }
            }
            listOfNotNull(row, gap)
        }
    }

    const val CHANGED_BY_YOU = "changed by you"

    const val FOOTNOTE = "Freestyle keeps no records: no best, no rank and no level."
}
