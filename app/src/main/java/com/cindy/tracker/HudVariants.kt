package com.cindy.tracker

import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import com.cindy.tracker.databinding.ActivityMainBinding

/** The three arrangements of the camera screen's chrome that #140 puts in front of the owner. */
enum class HudVariant(val label: String) {
    THIN("Thin bands"),
    NONE("No bands"),
    TODAY("Today's bands")
}

/**
 * PROTOTYPE #140 (spec #139), never merged, debug builds only.
 *
 * Re-arranges the views the camera screen already has between three layouts, live, without
 * touching the camera: the PreviewView, the OverlayView and every CameraX use case are left
 * alone, so the 480x640 analysis frame is the same in all three. Only the chrome around the
 * picture moves.
 *
 * All three variants carry the camera switch in the top row beside REC and MENU; the old
 * bottom-left FLIP is hidden in all of them (the activity does that), and END keeps the left
 * slot of the action row while a workout is live.
 */
class HudVariants(
    private val b: ActivityMainBinding,
    /** Sets the padding a band starts from, before the cutout is added, and re-applies it. */
    private val setBandBase: (View, Int, Int, Int, Int) -> Unit
) {
    var current = HudVariant.TODAY
        private set

    private val ctx = b.root.context
    private val d = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val root = b.root as ConstraintLayout

    // Where today's pieces live, so Today's bands can put them back.
    private class Home(val view: View, val parent: ViewGroup, val index: Int, val lp: ViewGroup.LayoutParams)

    private fun home(v: View) = Home(v, v.parent as ViewGroup, (v.parent as ViewGroup).indexOfChild(v), v.layoutParams)

    private val homes: List<Home> = listOf(
        b.statusRow,
        b.roundsLabel, b.rounds, b.exercise,
        b.btnUndo, b.repBlock, b.btnAddRep
    ).map(::home)

    private val topBg = b.bandTop.background
    private val bottomBg = b.bandBottom.background
    private val statusPad = intArrayOf(
        b.statusRow.paddingLeft, b.statusRow.paddingTop, b.statusRow.paddingRight, b.statusRow.paddingBottom
    )
    private val timerLp = b.timer.layoutParams as LinearLayout.LayoutParams

    // The compact count row (thin bands and no bands): round and movement on the left, the
    // number and its editors on the right.
    private val roundLine = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
    private val eyebrowStack = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    private val cluster = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }
    private val compactCount = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        visibility = View.GONE
    }

    // Lets the clock be a pill that does not stretch across the row (no bands).
    private val spacer = View(ctx).apply { visibility = View.GONE }

    init {
        compactCount.addView(eyebrowStack, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        compactCount.addView(cluster, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        eyebrowStack.addView(roundLine, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        // After the progress edge, which is the band's first child.
        b.bandBottom.addView(compactCount, 1, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        b.clockRow.addView(spacer, b.clockRow.indexOfChild(b.timer) + 1, LinearLayout.LayoutParams(0, 1, 1f))
    }

    /** Called once, from the first layout pass while Today's bands are still the ones showing. */
    fun captureToday() {
        b.zoneCorners.zoneTop = b.bandTop.bottom.toFloat()
        b.zoneCorners.zoneBottom = b.bandBottom.top.toFloat()
        Log.i(TAG, "today's zone: top=${b.bandTop.bottom} bottom=${b.bandBottom.top} of ${b.root.height}")
    }

    fun cycle(): HudVariant {
        val next = HudVariant.entries[(current.ordinal + 1) % HudVariant.entries.size]
        apply(next)
        return next
    }

    fun apply(variant: HudVariant) {
        current = variant
        when (variant) {
            HudVariant.TODAY -> {
                putEverythingBack()
                tune(compact = false)
                glass(false)
                b.zoneCorners.visibility = View.GONE
            }
            HudVariant.THIN -> {
                makeCompact()
                tune(compact = true)
                glass(false)
                b.zoneCorners.visibility = View.GONE
            }
            HudVariant.NONE -> {
                makeCompact()
                tune(compact = true)
                glass(true)
                b.zoneCorners.visibility = View.VISIBLE
            }
        }
        b.root.requestLayout()
        b.root.postDelayed({ measure() }, 400)
    }

    // ── moving the pieces ─────────────────────────────────────────────────────

    private fun putEverythingBack() {
        // Take them all out, then put each back at its old index; ascending order keeps indexes true.
        homes.forEach { (it.view.parent as? ViewGroup)?.removeView(it.view) }
        homes.sortedBy { it.index }.forEach {
            it.parent.addView(it.view, minOf(it.index, it.parent.childCount), it.lp)
        }
        b.eyebrowRow.visibility = View.VISIBLE
        b.countRow.visibility = View.VISIBLE
        compactCount.visibility = View.GONE
        b.statusRow.setPadding(statusPad[0], statusPad[1], statusPad[2], statusPad[3])
        b.statusRow.background = null
        b.exercise.gravity = Gravity.END
    }

    private fun makeCompact() {
        // Status line: a pill on the picture, below the top band.
        (b.statusRow.parent as? ViewGroup)?.removeView(b.statusRow)
        val pill = ConstraintLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topToBottom = b.bandTop.id
            startToStart = ConstraintLayout.LayoutParams.PARENT_ID
            endToEnd = ConstraintLayout.LayoutParams.PARENT_ID
            constrainedWidth = true
            topMargin = dp(8)
            marginStart = dp(16)
            marginEnd = dp(16)
        }
        // Just under the coach card in z-order, so the launch view, the tour and the countdown cover it.
        root.addView(b.statusRow, root.indexOfChild(b.coachCard), pill)
        b.statusRow.background = ContextCompat.getDrawable(ctx, R.drawable.glass_pill)
        b.statusRow.setPadding(dp(14), dp(6), dp(14), dp(6))

        listOf(b.roundsLabel, b.rounds, b.exercise, b.btnUndo, b.repBlock, b.btnAddRep).forEach {
            (it.parent as? ViewGroup)?.removeView(it)
        }
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        roundLine.addView(b.roundsLabel, LinearLayout.LayoutParams(wrap, wrap))
        roundLine.addView(b.rounds, LinearLayout.LayoutParams(wrap, wrap).apply { marginStart = dp(5) })
        b.exercise.gravity = Gravity.START
        eyebrowStack.addView(
            b.exercise,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, wrap).apply { topMargin = dp(2) }
        )
        val editor = dp(48)
        cluster.addView(b.btnUndo, LinearLayout.LayoutParams(editor, editor))
        cluster.addView(
            b.repBlock,
            LinearLayout.LayoutParams(wrap, wrap).apply { marginStart = dp(6); marginEnd = dp(6) }
        )
        cluster.addView(b.btnAddRep, LinearLayout.LayoutParams(editor, editor))
        b.eyebrowRow.visibility = View.GONE
        b.countRow.visibility = View.GONE
        compactCount.visibility = View.VISIBLE
    }

    /** Sizes only: the compact variants against the XML's own numbers. */
    private fun tune(compact: Boolean) {
        b.clockRow.layoutParams.height = dp(if (compact) 44 else 48)
        if (compact) setBandBase(b.bandTop, 0, 0, 0, dp(4)) else setBandBase(b.bandTop, 0, dp(14), 0, dp(11))
        setBandBase(b.bandBottom, 0, 0, 0, dp(if (compact) 8 else 16))

        (b.actionRow.layoutParams as ViewGroup.MarginLayoutParams).apply {
            height = dp(if (compact) 56 else 68)
            topMargin = dp(if (compact) 6 else 12)
        }
        b.btnStart.layoutParams.apply { width = dp(if (compact) 56 else 68); height = width }
        b.btnEnd.layoutParams.apply { width = dp(if (compact) 48 else 52); height = width }
        b.btnSkipExercise.layoutParams.apply { width = dp(if (compact) 48 else 52); height = width }

        if (compact) {
            b.reps.setAutoSizeTextTypeUniformWithConfiguration(24, 44, 1, TypedValue.COMPLEX_UNIT_SP)
            b.repsTarget.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        } else {
            b.reps.setAutoSizeTextTypeUniformWithConfiguration(30, 56, 1, TypedValue.COMPLEX_UNIT_SP)
            b.repsTarget.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
        }
        b.actionRow.requestLayout()
        b.clockRow.requestLayout()
    }

    /** No bands: the bands' own backgrounds go, and each control carries its own glass. */
    private fun glass(on: Boolean) {
        val switchIcons = listOf(b.btnSwitchTop, b.btnRec, b.btnMenu)
        if (on) {
            b.bandTop.background = null
            b.bandBottom.background = null
            timerLp.width = ViewGroup.LayoutParams.WRAP_CONTENT
            timerLp.weight = 0f
            spacer.visibility = View.VISIBLE
            b.timer.background = ContextCompat.getDrawable(ctx, R.drawable.glass_pill)
            b.timer.setPadding(dp(16), dp(4), dp(16), dp(4))
            switchIcons.forEach {
                it.background = ContextCompat.getDrawable(ctx, R.drawable.btn_glass)
                (it.layoutParams as LinearLayout.LayoutParams).marginStart = dp(8)
            }
            compactCount.background = ContextCompat.getDrawable(ctx, R.drawable.glass_pill)
            compactCount.setPadding(dp(18), dp(4), dp(8), dp(4))
            (compactCount.layoutParams as LinearLayout.LayoutParams).apply {
                marginStart = dp(16); marginEnd = dp(16); topMargin = dp(6)
            }
        } else {
            b.bandTop.background = topBg
            b.bandBottom.background = bottomBg
            timerLp.width = 0
            timerLp.weight = 1f
            spacer.visibility = View.GONE
            b.timer.background = null
            b.timer.setPadding(0, 0, 0, 0)
            switchIcons.forEach {
                it.background = null
                (it.layoutParams as LinearLayout.LayoutParams).marginStart = 0
            }
            compactCount.background = null
            compactCount.setPadding(dp(20), 0, dp(20), 0)
            (compactCount.layoutParams as LinearLayout.LayoutParams).apply {
                marginStart = 0; marginEnd = 0; topMargin = dp(4)
            }
        }
        b.timer.layoutParams = timerLp
    }

    // ── the numbers ───────────────────────────────────────────────────────────

    /**
     * One log line per applied variant, from the real layout: the window, what each band takes,
     * and the bright middle left between them. For No bands the bands are transparent, so
     * "opaque" is zero and "footprint" is what the controls still occupy.
     */
    private fun measure() {
        val h = b.root.height
        val w = b.root.width
        if (h == 0) return
        val top = b.bandTop.height
        val bottom = b.bandBottom.height
        val pill = if (b.statusRow.parent === root) b.statusRow.height + dp(8) else 0
        val opaque = if (current == HudVariant.NONE) 0 else top + bottom
        val footprint = top + bottom
        fun pct(v: Int) = "%.1f".format(100f * v / h)
        Log.i(
            TAG,
            "HUDMEASURE variant=$current window=${w}x$h top=${top}px bottom=${bottom}px " +
                "opaqueShare=${pct(opaque)}% footprintShare=${pct(footprint)}% " +
                "withStatusPill=${pct(footprint + pill)}% brightMiddle=${h - top - bottom}px " +
                "(${pct(h - top - bottom)}%) topPad=${b.bandTop.paddingTop}px"
        )
    }

    private companion object {
        const val TAG = "HudVariants"
    }
}
