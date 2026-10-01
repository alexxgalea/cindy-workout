package com.cindy.tracker

import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale
import kotlin.math.roundToInt

/**
 * One figure of the session at a glance: a label, a value and one line saying what it is made of.
 *
 * [speech] is what a screen reader says for the whole tile, so the label, the value and the
 * footnote arrive as one sentence rather than three unrelated fragments.
 */
data class StatTile(val label: String, val value: String, val footnote: String, val speech: String)

/** The six figures under the score, built from the attempt's own totals. */
object SessionTiles {

    /** No data is a dash, not a zero: nothing was timed, which is not the same as taking no time. */
    const val NONE = "—"

    /**
     * ROUNDS, REPS, TIME, then AVG ROUND, FASTEST, SLOWEST.
     *
     * [stats] is optional: without set times (an older record) the tiles still say everything the
     * attempt's own totals can, and nothing more. The rounds tile's footnote then falls back to
     * [Attempt.reps], the same loose count the headline already shows.
     */
    fun of(a: Attempt, stats: SessionStats?): List<StatTile> {
        val splits = a.roundSplitsMs
        val fastest = splits.minOrNull()
        val slowest = splits.maxOrNull()
        return listOf(
            rounds(a, stats),
            reps(a),
            time(a),
            average(a),
            extreme("FASTEST", "Fastest round", fastest, splits.indexOf(fastest)),
            extreme("SLOWEST", "Slowest round", slowest, splits.indexOf(slowest))
        )
    }

    private fun rounds(a: Attempt, stats: SessionStats?): StatTile {
        val leftover = stats?.let { it.unfinished?.reps ?: 0 } ?: a.reps
        // The reps into the next round come from the score, so a floor says "at least" here
        // too, on the tile and in the sentence read out for it.
        val atLeast = if (a.scoreIsLowerBound) "at least " else ""
        val into = "$leftover ${reps(leftover)} into round ${a.rounds + 1}"
        val footnote = when {
            leftover > 0 -> "${atLeast}+$into"
            a.rounds == 0 -> "none finished"
            else -> "all finished"
        }
        val speech = if (leftover > 0) {
            "Rounds: ${a.rounds}, plus ${atLeast}$into"
        } else {
            "Rounds: ${a.rounds}, $footnote"
        }
        return StatTile("ROUNDS", "${a.rounds}", footnote, speech)
    }

    private fun reps(a: Attempt): StatTile {
        val pace = SessionStats.repsPerMinute(a)
        val atLeast = a.scoreIsLowerBound
        // A floor says so on the tile and in the sentence read out for it: the camera lost the
        // athlete, so the true figure, and the pace made from it, can only be higher.
        val rate = pace?.let { "${"%.1f".format(Locale.US, it)} reps/min" }
        val parts = listOfNotNull(
            if (atLeast) "At least" else null,
            rate?.let { if (atLeast) "$it or more" else it },
            if (a.manualReps > 0) "${a.manualReps} tapped" else null
        )
        val footnote = parts.joinToString(" · ")
        val speech = buildString {
            append(if (atLeast) "Reps: at least ${a.totalReps}" else "Reps: ${a.totalReps}")
            if (pace != null) {
                append(", ${if (atLeast) "at least " else ""}${"%.1f".format(Locale.US, pace)} reps a minute")
            }
            if (a.manualReps > 0) append(", ${a.manualReps} of them tapped in")
        }
        return StatTile("REPS", "${a.totalReps}", footnote.ifEmpty { "banked" }, speech)
    }

    private fun time(a: Attempt): StatTile {
        val footnote = if (a.pausedMs > 0L) {
            "plus ${formatDuration(a.pausedMs)} paused"
        } else {
            "on the clock"
        }
        return StatTile(
            "TIME", formatDuration(a.durationMs), footnote,
            "Time: ${formatDuration(a.durationMs)} on the clock" +
                if (a.pausedMs > 0L) ", plus ${formatDuration(a.pausedMs)} paused" else ""
        )
    }

    private fun average(a: Attempt): StatTile {
        val avg = a.avgRoundMs ?: return StatTile(
            "AVG ROUND", NONE, "no full round", "Average round: no full round yet"
        )
        // Without round splits the figure is the clock over the rounds, which charges the
        // unfinished round to the average, and says so rather than passing as a mean of rounds.
        val footnote = if (a.roundSplitsMs.isNotEmpty()) {
            "over ${a.roundSplitsMs.size} ${rounds(a.roundSplitsMs.size)}"
        } else {
            "clock over rounds"
        }
        return StatTile(
            "AVG ROUND", formatDuration(avg), footnote,
            "Average round: ${formatDuration(avg)}, $footnote"
        )
    }

    private fun extreme(label: String, spoken: String, ms: Long?, index: Int): StatTile {
        if (ms == null) return StatTile(label, NONE, "no full round", "$spoken: no full round yet")
        val footnote = "round ${index + 1}"
        return StatTile(label, formatDuration(ms), footnote, "$spoken: ${formatDuration(ms)}, $footnote")
    }

    private fun reps(n: Int) = if (n == 1) "rep" else "reps"
    private fun rounds(n: Int) = if (n == 1) "round" else "rounds"
}

/**
 * The six [StatTile]s as a three-by-two grid of glass cards.
 *
 * Built in code like the rest of this page; every tile is one TalkBack node, with its children
 * hidden, the way [RecordsActivity]'s week tiles are.
 */
fun Context.statTileGrid(tiles: List<StatTile>): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    tiles.chunked(3).forEachIndexed { row, rowTiles ->
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            rowTiles.forEachIndexed { column, tile ->
                addView(statTile(tile), LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.MATCH_PARENT, 1f
                ).apply { if (column > 0) marginStart = dp(8) })
            }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { if (row > 0) topMargin = dp(8) })
    }
}

private fun Context.statTile(tile: StatTile): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    setBackgroundResource(R.drawable.glass_card)
    setPadding(dp(14), dp(12), dp(14), dp(12))
    addView(eyebrow(tile.label))
    addView(styledText(R.style.Cindy_MetricS, tile.value).apply {
        // A figure that does not fit shrinks rather than clipping or wrapping: "20:00" at the
        // style's size is too wide for a third of a narrow phone.
        setAutoSizeTextTypeUniformWithConfiguration(14, 22, 1, TypedValue.COMPLEX_UNIT_SP)
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(6) })
    addView(styledText(R.style.Cindy_Footnote, tile.footnote).apply {
        textSize = 11f
        maxLines = 3
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(2) })
    contentDescription = tile.speech
    isFocusable = true
    (0 until childCount).forEach {
        getChildAt(it).importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }
}

/**
 * Three columns, in the order the round is done: what each movement came to over the session.
 *
 * A line is left out where its figure is unknown (no finished set, tapped reps the record cannot
 * attribute) rather than shown as a dash, and the dot beside each name carries the same weight
 * mapping the round track and the Help page use.
 */
fun Context.movementCard(movements: List<MovementStat>, atLeast: Boolean = false): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    setBackgroundResource(R.drawable.glass_card)
    setPadding(dp(14), dp(14), dp(14), dp(14))
    movements.forEachIndexed { i, m ->
        addView(movementColumn(m, atLeast), LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ).apply { if (i > 0) marginStart = dp(10) })
    }
}

private fun Context.movementColumn(m: MovementStat, atLeast: Boolean): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    val lines = buildList {
        // The reps above come from the sets, which sum to the score, so they are a floor too.
        if (atLeast) add("at least")
        m.timeMs?.let { add("${formatDuration(it)} total") }
        m.averageCompleteSetMs?.let { add("${formatDuration(it)} a set") }
        m.shareOfClock?.let { add("${(it * 100).roundToInt()}% of set time") }
        m.tappedReps?.takeIf { it > 0 }?.let { add("$it tapped") }
    }
    val colour = movementColourRes(m.movement)

    addView(LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(View(context).apply { background = dotDrawable(colour) },
            LinearLayout.LayoutParams(dp(6), dp(6)).apply { marginEnd = dp(6) })
        addView(styledText(R.style.Cindy_Footnote, m.label).apply {
            maxLines = 2
        }, LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ))
    })
    addView(styledText(R.style.Cindy_MetricS, "${m.reps}").apply {
        setAutoSizeTextTypeUniformWithConfiguration(14, 22, 1, TypedValue.COMPLEX_UNIT_SP)
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(6) })
    lines.forEach { line ->
        addView(styledText(R.style.Cindy_Footnote, line).apply {
            textSize = 11f
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(3) })
    }

    contentDescription = buildString {
        append("${m.label}: ${m.reps} reps")
        lines.forEach { append(", $it") }
    }
    isFocusable = true
    (0 until childCount).forEach {
        getChildAt(it).importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }
}

/**
 * The weight of a movement, matching its 5:10:15 rep-scheme share: pull-ups brightest, squats
 * dimmest. The same mapping Help's workout card uses, so the three read the same everywhere.
 */
fun movementColourRes(movement: Exercise): Int = when (movement) {
    Exercise.PULLUP -> R.color.label
    Exercise.PUSHUP -> R.color.label_secondary
    Exercise.SQUAT -> R.color.label_tertiary
}
