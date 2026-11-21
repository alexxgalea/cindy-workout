package com.cindy.tracker

/**
 * One run of one movement's reps: [startMs]/[endMs] are the clock times of its first and last rep.
 * [changedByAthlete] is true once the athlete gave the set another movement on the session page.
 */
data class FreestyleSet(
    val movement: Exercise,
    val reps: Int,
    val startMs: Long,
    val endMs: Long,
    val changedByAthlete: Boolean = false
) {
    val lengthMs: Long get() = endMs - startMs
}

/** What lies between two sets: a Rest inside one movement, a Transition across two. */
enum class GapKind { REST, TRANSITION }

/** The time from one set's last rep to the next set's first. */
data class FreestyleGap(val kind: GapKind, val startMs: Long, val endMs: Long) {
    val lengthMs: Long get() = endMs - startMs
}

/** What [FreestyleSets.derive] gives back. Totals and per-movement figures all read from [sets]. */
data class DerivedSets(val sets: List<FreestyleSet>, val gaps: List<FreestyleGap>) {
    val totals: Map<Exercise, Int>
        get() = sets.groupBy { it.movement }.mapValues { (_, s) -> s.sumOf { it.reps } }

    fun timeInSets(movement: Exercise): Long = sets.filter { it.movement == movement }.sumOf { it.lengthMs }

    fun setCount(movement: Exercise): Int = sets.count { it.movement == movement }
}

/**
 * Set derivation (spec #188). Pure: the rep marks in, the sets and the gaps between them out.
 * Runs at STOP, and again after a set is relabelled by changing its marks' movement, so totals
 * are always derived from the sets.
 *
 * A set ends where the movement changes (the gap is a Transition) or where the gap since the
 * previous rep is longer than [REST_THRESHOLD_MS] inside one movement (the gap is a Rest).
 * Mirror this rule and constant in the Python twin.
 */
object FreestyleSets {

    /** PROVISIONAL: a later ticket measures it on the owner's films (about 10-15 s). */
    const val REST_THRESHOLD_MS = 12_000L

    fun derive(marks: List<RepMark>): DerivedSets {
        val sets = mutableListOf<FreestyleSet>()
        var movement: Exercise? = null
        var reps = 0
        var start = 0L
        var end = 0L
        fun close() {
            movement?.let { sets += FreestyleSet(it, reps, start, end) }
        }
        for (mark in marks.sortedBy { it.clockMs }) {
            val sameMovement = mark.movement == movement
            if (movement != null && sameMovement && mark.clockMs - end <= REST_THRESHOLD_MS) {
                reps++
                end = mark.clockMs
                continue
            }
            close()
            movement = mark.movement
            reps = 1
            start = mark.clockMs
            end = mark.clockMs
        }
        close()
        return DerivedSets(sets, gapsBetween(sets))
    }

    /** The gap between each pair of neighbouring [sets]: a Rest inside one movement, else a Transition. */
    fun gapsBetween(sets: List<FreestyleSet>): List<FreestyleGap> = sets.zipWithNext { a, b ->
        FreestyleGap(if (a.movement == b.movement) GapKind.REST else GapKind.TRANSITION, a.endMs, b.startMs)
    }

    /**
     * The attempt with set [index] given [to] as its movement: the set's reps move with it, the
     * totals are recomputed from the sets, and the set is marked as changed by the athlete.
     *
     * Neighbours are never merged. If the relabel makes two adjacent sets the same movement they
     * stay two sets and the gap between them reads as a Rest, which is what [gapsBetween] says of
     * any two neighbouring sets of one movement; this matches [derive], where a quiet spell
     * inside one movement ends a set. The Rest and Transition labels are not stored, so they
     * follow with no further work.
     *
     * Giving a set its own movement, or naming a set that is not there, returns [a] unchanged,
     * so a tap that decides nothing files nothing and marks nothing.
     */
    fun relabel(a: Attempt, index: Int, to: Exercise): Attempt {
        val set = a.freestyleSets.getOrNull(index) ?: return a
        if (set.movement == to) return a
        val sets = a.freestyleSets.toMutableList()
        sets[index] = set.copy(movement = to, changedByAthlete = true)
        val totals = DerivedSets(sets, emptyList()).totals
        return a.copy(freestyleSets = sets, movementTotals = Exercise.entries.filter { it in totals }.associateWith { totals.getValue(it) })
    }
}
