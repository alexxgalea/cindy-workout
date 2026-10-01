package com.cindy.tracker

import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * What the round-splits chart draws and says: each complete round's time, where it can be split
 * by movement, the round still running when the clock stopped, and the words for whichever bar
 * is selected.
 *
 * Pure, like [Comparisons] and [Progress]: no Android types, so the arithmetic and the
 * decisions about what the record can honestly support are testable without a phone. Colour is
 * left to the caller for the same reason; [Versus] says which way a gap went and nothing about
 * how to paint it.
 */
object RoundSplits {

    /** A round is these three movements, in this order, and `SplitBook` files them that way. */
    private val CYCLE = Exercise.entries

    /** The reps one round asks for in all, which is the denominator under an unfinished round. */
    val ROUND_TARGET: Int = CYCLE.sumOf { it.target }

    /**
     * How far a round's movement times may sit from the round's own split before they stop being
     * believed. `SplitBook` and the round timer both start from the same moment and are read from
     * the same clock, so a healthy record agrees to within a few milliseconds; a gap of seconds
     * means one of the two was cut short, and stacking it would draw a bar whose parts disagree
     * with its height.
     */
    private const val SUM_TOLERANCE_MS = 2_000L

    /** An unfinished round shorter than this is the athlete still putting the bar away. */
    private const val MIN_UNFINISHED_MS = 1_000L

    /**
     * One bar.
     *
     * @param ms the round's time; for an [unfinished] round, the clock time since the last one.
     * @param sets the time of each movement in [CYCLE] order, or null when the record cannot
     *   say. A finished round has all three; an unfinished one has the movements it had already
     *   left behind, which may be none.
     * @param byHand a rep in one of its sets was tapped in rather than seen.
     * @param reps what had been counted in an [unfinished] round, or null when the record does
     *   not allow that to be said.
     * @param atLeast [reps] is a floor, because the camera lost the athlete for long enough that
     *   the score it derives from is a lower bound.
     */
    data class Bar(
        val round: Int,
        val ms: Long,
        val sets: List<Long>?,
        val byHand: Boolean = false,
        val unfinished: Boolean = false,
        val reps: Int? = null,
        val atLeast: Boolean = false
    )

    /** The bars, in round order, with the unfinished round (if any) last. */
    data class Split(val bars: List<Bar>, val fastest: Int, val averageMs: Long) {
        val finished: List<Bar> get() = bars.filter { !it.unfinished }
        val hasBreakdown: Boolean get() = bars.any { !it.unfinished && it.sets != null }
        val hasUnfinished: Boolean get() = bars.lastOrNull()?.unfinished == true
    }

    /** Which way a gap to the comparison went. [faster] is null when the two are level. */
    data class Versus(val text: String, val faster: Boolean?)

    data class Readout(val title: String, val detail: String, val versus: Versus?) {
        /** One sentence for a screen reader, which reads the row as a unit. */
        fun spoken(): String = listOfNotNull(title, detail, versus?.text).joinToString(". ")
    }

    /** Null when the attempt has no complete round to chart. */
    fun of(a: Attempt): Split? {
        val splits = a.roundSplitsMs
        if (splits.isEmpty()) return null

        val bars = splits.mapIndexed { i, ms ->
            val sets = breakdown(a, i, ms)
            Bar(
                round = i + 1, ms = ms, sets = sets,
                byHand = sets != null && a.setSplits.subList(i * 3, i * 3 + 3).any { it.manualReps > 0 }
            )
        }.toMutableList()
        unfinished(a)?.let { bars += it }

        return Split(bars, fastest = splits.indexOf(splits.min()), averageMs = splits.sum() / splits.size)
    }

    /**
     * Round [i]'s three movement times, or null when they cannot be trusted.
     *
     * Positional: round `i` is sets `3i` to `3i + 2`, which holds only while the list is the
     * unbroken cycle `SplitBook` writes. A list cut short or reordered shifts every later round
     * onto the wrong movement, and each of those then fails the order check on its own, so no
     * round needs to know about the others. A round that skipped a movement still has its set:
     * SKIP files it at the reps it reached, so the order is intact and only its reps are short.
     */
    private fun breakdown(a: Attempt, i: Int, roundMs: Long): List<Long>? {
        if (i * 3 + 3 > a.setSplits.size) return null
        val sets = a.setSplits.subList(i * 3, i * 3 + 3)
        if (sets.map { it.movement } != CYCLE) return null
        val times = sets.map { it.ms }
        return times.takeIf { abs(it.sum() - roundMs) <= SUM_TOLERANCE_MS }
    }

    /**
     * The round the clock stopped in, if it had run for long enough to be one.
     *
     * Its time is whatever the round splits did not account for, both read from the workout
     * clock. Its reps come from [StravaSets], which already knows how to put the movement still
     * running back in and refuses a record that does not add up; that null is honoured here as
     * "reps unknown" rather than replaced with a figure worked out from the round count.
     */
    private fun unfinished(a: Attempt): Bar? {
        val done = a.roundSplitsMs.size
        val trailing = a.durationMs - a.roundSplitsMs.sum()
        if (trailing < MIN_UNFINISHED_MS) return null

        val left = a.setSplits.drop(done * 3)
        val inOrder = left.size < CYCLE.size && left.indices.all { left[it].movement == CYCLE[it] }
        val sets = if (inOrder && a.setSplits.size >= done * 3) left.map { it.ms } else null

        // The set list is positional, so it speaks for this round only when the finished rounds
        // account for exactly the sets before it.
        val reps = StravaSets.from(a)
            ?.takeIf { a.setSplits.size / 3 == done }
            ?.filter { it.round == done + 1 }
            ?.sumOf { it.reps }
        return Bar(
            round = done + 1, ms = trailing, sets = sets, unfinished = true, reps = reps,
            atLeast = reps != null && a.scoreIsLowerBound,
            byHand = inOrder && left.any { it.manualReps > 0 }
        )
    }

    /** The comparison's split at each bar's round, null where it has none (or the bar is open). */
    fun reference(split: Split, reference: Attempt?): List<Long?> =
        split.bars.map { bar ->
            if (bar.unfinished) null else reference?.roundSplitsMs?.getOrNull(bar.round - 1)
        }

    /**
     * The three movements' names for this athlete: their own variant's plural where they changed
     * it, the plain name where they did not, so a knee push-up session never reads "push-ups".
     */
    fun movementNames(profile: CindyProfile?): List<String> = CYCLE.map { movement ->
        val plain = movement.label.lowercase()
        if (profile == null) return@map plain
        val own = when (movement) {
            Exercise.PULLUP -> profile.pull.takeIf { it != CindyProfile.STANDARD.pull }?.plural
            Exercise.PUSHUP -> profile.push.takeIf { it != CindyProfile.STANDARD.push }?.plural
            Exercise.SQUAT -> profile.squat.takeIf { it != CindyProfile.STANDARD.squat }?.plural
        }
        own ?: plain
    }

    /**
     * The words for [selected] (null for none), against [reference] where it has a split at the
     * same round.
     *
     * @param kind which comparison [reference] is, since "your best's round 5" and "round 5 last
     *   time" are not the same sentence with a different noun.
     */
    fun readout(
        a: Attempt,
        split: Split,
        selected: Int?,
        reference: Attempt?,
        kind: Comparisons.Kind?
    ): Readout {
        val bar = selected?.let { split.bars.getOrNull(it) } ?: return idle(split)
        val names = movementNames(a.profile)

        if (bar.unfinished) {
            val title = "Round ${bar.round} · ${formatDuration(bar.ms)} so far"
            val parts = mutableListOf<String>()
            bar.reps?.let { parts += "${if (bar.atLeast) "at least " else ""}$it of $ROUND_TARGET reps" }
            parts += "not a finished round"
            val timed = timedSets(names, bar.sets)
            val detail = listOfNotNull(parts.joinToString(" · "), timed, handNote(bar)).joinToString(". ")
            return Readout(title, detail, null)
        }

        val title = "Round ${bar.round} · ${formatDuration(bar.ms)}"
        val detail = (timedSets(names, bar.sets) ?: "No per-movement times for this round")
            .let { if (bar.byHand) "$it. ${handNote(bar)}" else it }
        val ref = reference?.roundSplitsMs?.getOrNull(bar.round - 1)
        return Readout(title, detail, if (ref == null || kind == null) null else versus(bar, ref, kind))
    }

    /** What the row says before anything is chosen. */
    private fun idle(split: Split): Readout {
        val fastest = split.bars[split.fastest]
        val title = buildString {
            append("Fastest: round ${fastest.round} at ${formatDuration(fastest.ms)}")
            if (split.finished.size > 1) append(" · average ${formatDuration(split.averageMs)}")
        }
        return Readout(title, "Tap or drag across the bars to see where each round's time went.", null)
    }

    /** "Pull-ups 0:41 · push-ups 0:52 · squats 1:15", or just what a round had reached. */
    private fun timedSets(names: List<String>, sets: List<Long>?): String? {
        if (sets.isNullOrEmpty()) return null
        return sets.mapIndexed { i, ms -> "${names[i]} ${formatDuration(ms)}" }
            .joinToString(" · ")
            .replaceFirstChar { it.uppercase() }
    }

    private fun handNote(bar: Bar): String? =
        if (bar.byHand) "Some reps in this round were added by hand" else null

    private fun versus(bar: Bar, referenceMs: Long, kind: Comparisons.Kind): Versus {
        val gapMs = referenceMs - bar.ms
        val seconds = (abs(gapMs) / 1000.0).roundToLong()
        val against = when (kind) {
            Comparisons.Kind.BEST -> "your best's round ${bar.round}"
            Comparisons.Kind.LAST -> "round ${bar.round} last time"
        }
        if (seconds == 0L) return Versus("Level with $against", null)
        val gap = if (seconds < 60) "$seconds s" else formatDuration(seconds * 1000L)
        val faster = gapMs > 0
        return Versus("$gap ${if (faster) "faster" else "slower"} than $against", faster)
    }
}
