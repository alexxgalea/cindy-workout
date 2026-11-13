package com.cindy.tracker

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import android.text.style.MetricAffectingSpan
import java.util.Locale

/**
 * What the camera screen's bottom band prints while the athlete reads it from the bar: the figure
 * ("3/5") and the line under it ("Pull-ups · Round 2").
 *
 * Both are one piece of text in one view, so the count, the slash and the target can only ever be
 * one size and one weight: no span here changes either, and only colour steps down. One view is
 * also what lets the whole figure shrink together when it has to, instead of the count and the
 * target ending up at two sizes.
 */
object Scoreboard {

    /**
     * The count, a slash and the target. The count has no colour of its own, so it takes the
     * view's, which is how a banked rep pulses it; the slash is the quietest and the target
     * sits between. With no [target] it is the count alone, with no slash.
     */
    fun figure(count: String, target: String?, slash: Int, quiet: Int): CharSequence {
        val text = SpannableStringBuilder(count)
        if (target.isNullOrEmpty()) return text
        text.append(target)
        // The target is passed as "/15", as the activity has always built it: the slash is its
        // first character.
        text.setSpan(ForegroundColorSpan(slash), count.length, count.length + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        text.setSpan(ForegroundColorSpan(quiet), count.length + 1, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return text
    }

    /**
     * The movement in sentence case, a middle dot, then the round. The round alone is set in
     * tabular figures, so it does not shuffle sideways as it changes; the movement's words keep
     * the proportional ones a sentence reads best in.
     */
    fun line(movement: String, round: Int): CharSequence {
        val text = SpannableStringBuilder(sentenceCase(movement)).append(" · Round ")
        val from = text.length
        text.append(round.toString())
        text.setSpan(TabularFigures(), from, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return text
    }

    /** What a screen reader says for [line]: no dot to read out. */
    fun spokenLine(movement: String, round: Int): String = "${sentenceCase(movement)}, round $round"

    /** "PULL-UPS" as "Pull-ups": the engine's labels are in capitals, the scoreboard's line is not. */
    fun sentenceCase(label: String): String =
        label.lowercase(Locale.ROOT).replaceFirstChar { it.uppercase(Locale.ROOT) }

    private class TabularFigures : MetricAffectingSpan() {
        override fun updateDrawState(paint: TextPaint) = apply(paint)
        override fun updateMeasureState(paint: TextPaint) = apply(paint)
        private fun apply(paint: TextPaint) {
            val features = paint.fontFeatureSettings.orEmpty()
            if ("tnum" !in features) paint.fontFeatureSettings = if (features.isEmpty()) "tnum" else "$features, tnum"
        }
    }
}
