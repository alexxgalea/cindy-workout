package com.cindy.tracker

import android.content.res.ColorStateList
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.updateLayoutParams
import com.cindy.tracker.databinding.ActivityMainBinding

/**
 * How the camera screen's bottom band is drawn for the distance the athlete is at.
 *
 * While the clock runs they are 2 to 3 m away, cannot touch the phone and cannot read small text:
 * the band is the scoreboard, a 96 sp figure over a quiet row of 48 dp controls. In idle, setup
 * and a pause they are at the phone, at arm's length, about to press something: the controls come
 * forward and are named. A finished workout sits behind the session page and is drawn as idle.
 *
 * Both layouts are the one view hierarchy and the one band height, so the change between them is
 * at once, with no animation, and the picture above the band never moves. What a control is, and
 * whether it answers, is still [CameraControls]'s; this only decides how it looks and where.
 */
object BottomBand {

    /** Whether the athlete is at the bar, reading the scoreboard, or at the phone, pressing. */
    fun atTheBar(state: WorkoutState) = state == WorkoutState.RUNNING

    /**
     * Draws the band for [state]. [panel] says which controls are there and which answer, and
     * [statusBlank] whether the status line has anything to say (only idle cares: see
     * [ControlNames.pillShown]). [coachCovers] keeps the pill out of the way of the
     * start-position card, which hangs from its bottom edge.
     */
    fun apply(
        hud: ActivityMainBinding,
        state: WorkoutState,
        panel: CameraControlPanel,
        statusBlank: Boolean,
        coachCovers: Boolean = false
    ) {
        val bar = atTheBar(state)
        val context = hud.root.context

        // ── what each control is: there or not, answering or dimmed, and its spoken name ──
        show(hud.btnEnd, panel[CameraControl.END])
        capsule(hud, panel[CameraControl.MINUS], panel[CameraControl.PLUS])
        show(hud.btnStart, panel[CameraControl.SHUTTER])
        show(hud.btnSkipExercise, panel[CameraControl.SKIP])
        val res = context.resources
        fun dim(id: Int) = res.getDimensionPixelSize(id)
        fun dp(value: Int) = (value * res.displayMetrics.density).toInt()

        // ── the figure zone: at the phone the line moves up into the zone, under a 56 sp figure ──
        hud.reps.ceilingSp(if (bar) FIGURE_AT_BAR_SP else FIGURE_AT_PHONE_SP)
        hud.reps.updateLayoutParams<ViewGroup.LayoutParams> { height = dp(if (bar) 96 else 72) }
        hud.movementLine.updateLayoutParams<LinearLayout.LayoutParams> {
            // The line takes the 24 dp the zone has left under the figure and adds no height.
            topMargin = if (bar) 0 else -dp(24)
            marginStart = if (bar) 0 else dp(8)
            marginEnd = if (bar) 0 else dp(72)
        }

        // ── the control row ──
        hud.controlRow.updateLayoutParams<LinearLayout.LayoutParams> {
            topMargin = dp(if (bar) 16 else 8)
            height = dim(if (bar) R.dimen.shutter else R.dimen.shutter_near)
        }
        val side = dim(if (bar) R.dimen.shutter else R.dimen.control_near)
        val disc = dim(if (bar) R.dimen.shutter else R.dimen.shutter_near)
        // END and SKIP stay centred 40 dp from their edges as they grow.
        val edge = 40 * res.displayMetrics.density - side / 2f
        hud.btnEnd.size(side, dp(if (bar) 14 else 16)) { marginStart = edge.toInt() }
        hud.btnSkipExercise.size(side, dp(if (bar) 14 else 16)) { marginEnd = edge.toInt() }
        hud.btnStart.size(disc, dp(if (bar) 14 else 21)) {}
        // While the clock runs the shutter is a glass circle like its neighbours, so the row is
        // quiet under the figure the athlete reads from the bar. At the phone it is the white
        // disc, the one filled control, and the screen's one primary action.
        hud.btnStart.setBackgroundResource(if (bar) R.drawable.btn_glass else R.drawable.btn_shutter)
        hud.btnStart.imageTintList =
            ColorStateList.valueOf(context.getColor(if (bar) R.color.label else R.color.on_primary))

        // ── the names ──
        val names = ControlNames.of(state, panel)
        hud.controlNames.visibility = if (bar) View.GONE else View.VISIBLE
        hud.nameEnd.name(names.end)
        hud.nameShutter.name(names.shutter)
        hud.nameSkip.name(names.skip)
        hud.idleLine.name(names.idleLine)

        pill(hud, state, statusBlank, coachCovers)
    }

    /**
     * The coaching pill on the picture: there in setup, a pause and while counting, and in idle
     * only while the status line carries something the athlete has to be told. INVISIBLE rather
     * than GONE while the start-position card covers it, because the card hangs off its edge.
     */
    fun pill(hud: ActivityMainBinding, state: WorkoutState, statusBlank: Boolean, coachCovers: Boolean) {
        hud.statusRow.visibility = when {
            !ControlNames.pillShown(state, statusBlank) -> View.GONE
            coachCovers -> View.INVISIBLE
            else -> View.VISIBLE
        }
    }

    /**
     * Draws one control from what [CameraControls] says it is. Which controls are there, which
     * are dimmed and what each is called all live in that one table; this is only how the answer
     * looks. A dimmed control is faded and keeps its place.
     */
    fun show(view: View, control: ControlState) {
        view.visibility = if (control.present) View.VISIBLE else View.GONE
        view.isEnabled = control.enabled
        view.alpha = if (control.enabled) 1f else DIMMED
        view.contentDescription = control.name
    }

    /**
     * The − | + capsule. When neither editor answers, the capsule is dimmed as one piece, its glass
     * with its two marks, and keeps its place; the marks are then drawn whole inside it, so they
     * are not dimmed twice over. Otherwise each mark is drawn as [show] draws any control.
     */
    private fun capsule(hud: ActivityMainBinding, minus: ControlState, plus: ControlState) {
        show(hud.btnUndo, minus)
        show(hud.btnAddRep, plus)
        val off = !minus.enabled && !plus.enabled
        hud.stepper.alpha = if (off) DIMMED else 1f
        if (off) {
            hud.btnUndo.alpha = 1f
            hud.btnAddRep.alpha = 1f
        }
    }

    private fun TextView.name(text: String?) {
        visibility = if (text == null) View.GONE else View.VISIBLE
        if (text != null && this.text.toString() != text) this.text = text
    }

    private fun View.size(side: Int, padding: Int, margins: FrameLayout.LayoutParams.() -> Unit) {
        updateLayoutParams<FrameLayout.LayoutParams> {
            width = side
            height = side
            margins()
        }
        setPadding(padding, padding, padding, padding)
    }

    /** What an unavailable control fades to: plainly off, still plainly there. */
    const val DIMMED = 0.3f

    private const val FIGURE_AT_BAR_SP = 96f
    private const val FIGURE_AT_PHONE_SP = 56f
}
