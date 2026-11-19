package com.cindy.tracker

import android.content.Context
import android.graphics.Typeface
import android.view.View
import android.widget.TextView
import androidx.constraintlayout.widget.ConstraintLayout

/**
 * The line on the camera screen that says what recognition makes of the athlete: the position, and
 * once a movement is recognised its name and the reps recognition saw, for example
 * `on the floor · PUSH-UPS · 3`. Debug builds only: [MainActivity] makes one inside `if (BuildConfig.DEBUG)` and nothing else does, so a
 * release build never draws it, speaks it or stores it.
 *
 * It exists so recognition can be tried at the gym in a few seconds, with or without a workout
 * running. It owns its own [Recogniser], separate from the workout engine's counters, and changes
 * nothing that is counted, banked, saved or spoken.
 *
 * Threads: [feed] runs on the analysis thread for every analysed frame, in order, because the
 * recogniser's timers need them all and the UI hand-off drops all but the newest. [reset] and
 * [show] run on the main thread. The recogniser is shared between the first two, so both take
 * [lock].
 */
internal class RecognitionLine(context: Context, private var profile: CindyProfile = CindyProfile.STANDARD) {

    private var recogniser = Recogniser(profile)
    private val lock = Any()

    /** What the line is saying now, so a frame that restates it does not redraw it. Main thread only. */
    private var shown: String? = null

    val view = TextView(context).apply {
        typeface = Typeface.MONOSPACE
        textSize = 12f
        setTextColor(context.getColor(R.color.label))
        setBackgroundColor(context.getColor(R.color.band_top))
        val across = (8 * resources.displayMetrics.density).toInt()
        val down = (4 * resources.displayMetrics.density).toInt()
        setPadding(across, down, across, down)
        maxLines = 1
        // A debug aid for the person holding the phone, not something TalkBack should read out.
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        text = say(Recognition(Position.NONE))
    }

    /**
     * Puts the line on the picture, at the start edge just above [above], the bottom band. It sits
     * in the bright middle between the bands and adds height to neither, so the picture and the
     * analysis frame do not move.
     */
    fun attachTo(root: ConstraintLayout, above: View, marginPx: Int) {
        root.addView(
            view,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.WRAP_CONTENT,
                ConstraintLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                startToStart = ConstraintLayout.LayoutParams.PARENT_ID
                bottomToTop = above.id
                marginStart = marginPx * 2
                bottomMargin = marginPx
            }
        )
    }

    /** Analysis thread: one analysed frame. Returns what recognition makes of the athlete after it. */
    fun feed(keypoints: Array<Keypoint>, now: Long, identityStable: Boolean): Recognition =
        synchronized(lock) { recogniser.onFrame(keypoints, now, identityStable) }

    /**
     * Main thread: the athlete has changed the variation of a movement, so recognise with the new
     * one. Starts fresh, as a rebuilt engine does. Nothing happens when the profile is the same.
     */
    fun useProfile(movements: CindyProfile) {
        synchronized(lock) {
            if (movements == profile) return
            profile = movements
            recogniser = Recogniser(movements)
        }
        show(Recognition(Position.NONE))
    }

    /**
     * Main thread: a workout has started or the camera has been switched, so start fresh, and say
     * so at once rather than when the next frame arrives.
     */
    fun reset() {
        synchronized(lock) { recogniser.reset() }
        show(Recognition(Position.NONE))
    }

    /** Main thread: says what [recognition] says, redrawing only when it changed. */
    fun show(recognition: Recognition) {
        val line = say(recognition)
        if (line == shown) return
        shown = line
        view.text = line
    }

    private fun say(recognition: Recognition): String {
        val movement = recognition.movement ?: return recognition.position.label
        return "${recognition.position.label} · ${movement.label} · ${recognition.tally.getValue(movement)}"
    }
}
