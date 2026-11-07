package com.cindy.tracker

import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/**
 * One figure of the session at a glance: a label, a value and one line saying what it is made of.
 *
 * [speech] is what a screen reader says for the whole tile, so the label, the value and the
 * footnote arrive as one sentence rather than three unrelated fragments.
 */
data class StatTile(val label: String, val value: String, val footnote: String, val speech: String)

/**
 * The round figures under the lead: the average round, the fastest and the slowest.
 *
 * The score, the reps and the clock are [SessionLead]'s, so they are not said again here. A tile
 * with nothing to say is left out rather than shown as a dash, so a session without a full round
 * has no tiles at all.
 */
object SessionTiles {

    /**
     * AVG, FASTEST, SLOWEST, each only when the attempt can give it. An older record without
     * round splits still has an average (the clock over the rounds, and it says so) but no
     * extremes. [stats] is unused now that the loose reps moved to [SessionLead]; callers that
     * hold it keep passing it.
     */
    @Suppress("UNUSED_PARAMETER")
    fun of(a: Attempt, stats: SessionStats?): List<StatTile> {
        val splits = a.roundSplitsMs
        val fastest = splits.minOrNull()
        val slowest = splits.maxOrNull()
        return listOfNotNull(
            average(a),
            fastest?.let { extreme("FASTEST", "Fastest round", it, splits.indexOf(it)) },
            slowest?.let { extreme("SLOWEST", "Slowest round", it, splits.indexOf(it)) }
        )
    }

    private fun average(a: Attempt): StatTile? {
        val avg = a.avgRoundMs ?: return null
        // Without round splits the figure is the clock over the rounds, which charges the
        // unfinished round to the average, and says so rather than passing as a mean of rounds.
        val footnote = if (a.roundSplitsMs.isNotEmpty()) {
            "over ${a.roundSplitsMs.size} ${rounds(a.roundSplitsMs.size)}"
        } else {
            "clock over rounds"
        }
        return StatTile(
            "AVG", formatDuration(avg), footnote,
            "Average round: ${formatDuration(avg)}, $footnote"
        )
    }

    private fun extreme(label: String, spoken: String, ms: Long, index: Int): StatTile {
        val footnote = "round ${index + 1}"
        return StatTile(label, formatDuration(ms), footnote, "$spoken: ${formatDuration(ms)}, $footnote")
    }

    private fun rounds(n: Int) = if (n == 1) "round" else "rounds"
}

/**
 * The [StatTile]s as a row of glass cards.
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
    addView(eyebrow(tile.label).apply {
        // One line that shrinks to fit, so no label is ever cut mid-word, whatever the font scale
        // or the width of the phone. It needs the full width of the tile to have anything to shrink
        // into, so it matches the parent rather than wrapping its text.
        maxLines = 1
        // A shrunk label is a shorter line, which would lift its tile's figure above its
        // neighbours' at a large font scale. Every eyebrow keeps the height of the unshrunk
        // style, read before autosize takes over, so the figures start level across the row.
        minHeight = lineHeight
        setAutoSizeTextTypeUniformWithConfiguration(8, 11, 1, TypedValue.COMPLEX_UNIT_SP)
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ))
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
    // A long adaptive label ("band-assisted pull-ups") wraps; every label then reserves two
    // lines, so the three figures stay level. In the ordinary case no line is wasted.
    val tall = movements.any { it.label.length > LONG_LABEL }
    movements.forEachIndexed { i, m ->
        addView(movementColumn(m, atLeast, tall), LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ).apply { if (i > 0) marginStart = dp(10) })
    }
}

/** Past this many characters a label no longer fits one line in a third of a phone. */
private const val LONG_LABEL = 10

private fun Context.movementColumn(m: MovementStat, atLeast: Boolean, tall: Boolean): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    val lines = buildList {
        m.timeMs?.let { add("${formatDuration(it)} total") }
        m.averageCompleteSetMs?.let { add("${formatDuration(it)} a set") }
        m.shareOfClock?.let { add("${(it * 100).roundToInt()}% of set time") }
        m.tappedReps?.takeIf { it > 0 }?.let { add("$it tapped") }
    }
    val colour = movementColourRes(m.movement)

    addView(LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.TOP
        // On the first line of the label, wherever it wraps.
        addView(View(context).apply { background = dotDrawable(colour) },
            LinearLayout.LayoutParams(dp(6), dp(6)).apply { marginEnd = dp(6); topMargin = dp(5) })
        addView(styledText(R.style.Cindy_Footnote, m.label).apply {
            maxLines = 2
            if (tall) minLines = 2
        }, LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ))
    })
    // The reps come from the sets, which sum to the score, so they are a floor too: said between
    // the name and the figure, where it reads as "pull-ups, at least, 75".
    if (atLeast) {
        addView(styledText(R.style.Cindy_Footnote, "at least").apply {
            textSize = 11f
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(4) })
    }
    addView(styledText(R.style.Cindy_MetricS, "${m.reps}").apply {
        setAutoSizeTextTypeUniformWithConfiguration(14, 22, 1, TypedValue.COMPLEX_UNIT_SP)
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(if (atLeast) 0 else 6) })
    lines.forEach { line ->
        addView(styledText(R.style.Cindy_Footnote, line).apply {
            textSize = 11f
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(3) })
    }

    contentDescription = buildString {
        append("${m.label}: ${if (atLeast) "at least " else ""}${m.reps} reps")
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
