package com.cindy.tracker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.os.Handler
import android.os.Looper
import android.view.animation.LinearInterpolator

/** What a change of the scoreboard's figure says, and so how it moves. */
enum class FigureMotion {
    /** The figure changed, and no rep was banked or taken back by it: it just changes. */
    NONE,

    /** A rep was banked: the changed digits roll up and the count pulses green. */
    BANKED,

    /** A rep was taken back: the changed digits roll down, and nothing is green. */
    TAKEN_BACK;

    companion object {
        /**
         * How the figure moves for the frame that carried [event], from the engine's banked total
         * before it, [before], to after it, [after].
         *
         * Read off the total, never off the count on show: the count drops to 0 both when a set
         * is finished and when it is skipped, and only the first banked a rep. Only a frame with
         * an event moves the figure. A state frame can be drawn after an event it is older than,
         * and a new workout clears the score; neither is a rep banked or taken back.
         */
        fun of(event: RepEvent, before: Int, after: Int): FigureMotion = when {
            event == RepEvent.NONE -> NONE
            after > before -> BANKED
            after < before -> TAKEN_BACK
            else -> NONE
        }
    }
}

/**
 * The scoreboard's figure, "3/5", written only when it changes, and moved when a rep is banked
 * or taken back.
 *
 * The count, the slash and the target are one piece of text in one view (see [Scoreboard]), so
 * the whole figure shrinks together and is never two sizes. The count takes the view's colour,
 * which [colour] sets and a banked rep's pulse borrows for a moment; the slash and the target
 * are quieter.
 *
 * The motion is decoration. The new value is in the view the moment [show] is called, so it
 * never waits for the motion, and the motion never holds back the count, the voice or the next
 * rep: a rep banked mid-pulse starts it again from the value on show.
 */
class ScoreboardFigure(private val view: FitFigureView) {

    private val context = view.context
    private val slash = context.getColor(R.color.label_tertiary)
    private val quiet = context.getColor(R.color.label_secondary)
    private val ok = context.getColor(R.color.state_ok)

    private var shownCount: String? = null
    private var shownTarget: String? = null
    private var spoken: String? = null

    /** The count's own colour, which a pulse returns to. */
    private var base: Int = view.currentTextColor

    private var motion: ValueAnimator? = null

    fun show(count: String, target: String = "", how: FigureMotion = FigureMotion.NONE) {
        if (shownCount == count && shownTarget == target) return
        val was = shownCount
        shownCount = count
        shownTarget = target
        view.text = Scoreboard.figure(count, target, slash, quiet)
        stop()
        if (how == FigureMotion.NONE || was == null) return
        play(was, count, banked = how == FigureMotion.BANKED)
    }

    fun spoken(value: String) {
        if (spoken == value) return
        spoken = value
        view.contentDescription = value
    }

    fun colour(argb: Int) {
        base = argb
        if (motion == null) view.setTextColor(argb)
    }

    private fun play(from: String, to: String, banked: Boolean) {
        // With the system's animations off nothing moves, but a banked rep still turns the
        // count green for the length of the pulse: the colour is the answer, not decoration.
        if (!ValueAnimator.areAnimatorsEnabled()) {
            if (banked) {
                view.setTextColor(ok)
                clock.postDelayed(unpulse, PULSE_MS)
            }
            return
        }
        view.startRoll(from, to, if (banked) FitFigureView.Roll.UP else FitFigureView.Roll.DOWN)
        if (banked) view.setTextColor(ok)
        motion = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = if (banked) PULSE_MS else ROLL_MS
            interpolator = LinearInterpolator()
            addUpdateListener {
                val ms = it.currentPlayTime
                if (ms >= ROLL_MS) view.endRoll() else view.rollTo(ms.toFloat() / ROLL_MS)
                if (banked) view.setTextColor(pulseAt(ms))
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (motion !== animation) return
                    motion = null
                    settle()
                }
            })
            start()
        }
    }

    /** Stops any motion under way and leaves the figure still, in its own colour. */
    private fun stop() {
        clock.removeCallbacks(unpulse)
        val running = motion
        motion = null
        running?.cancel()
        settle()
    }

    /** Not the view's own queue, which holds a post back until the view is on screen. */
    private val clock = Handler(Looper.getMainLooper())

    /** The end of a pulse played without animation. */
    private val unpulse = Runnable { settle() }

    private fun settle() {
        view.endRoll()
        view.setTextColor(base)
    }

    /** Green for the first 60% of the pulse, as the mock has it, then a blend back to the count's colour. */
    private fun pulseAt(ms: Long): Int {
        if (ms <= HOLD_MS) return ok
        if (ms >= PULSE_MS) return base
        val t = (ms - HOLD_MS).toFloat() / (PULSE_MS - HOLD_MS)
        return ArgbEvaluator().evaluate(t, ok, base) as Int
    }

    private companion object {
        /** The mock's timings (bands-two.js TIMING): the roll, and the whole pulse. */
        const val ROLL_MS = 150L
        const val PULSE_MS = 300L
        const val HOLD_MS = 180L
    }
}
