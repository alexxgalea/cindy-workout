package com.cindy.tracker

import android.animation.ValueAnimator
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import com.cindy.tracker.databinding.ActivityMainBinding

/**
 * What the scoreboard reads while a workout is live: the figure, the line under it, the progress
 * edge, and the next set over the first two for a moment when the movement changes.
 *
 * Fed every frame the engine hands the camera screen. When a set is finished the band holds the
 * last rep's figure while its roll and pulse play, shows the next set for [NextSet.SHOWN_MS], then
 * the new set as the engine already has it. The state frames that arrive meanwhile are kept, not
 * drawn, and the newest of them is what the band returns to. Any event ends the hold at once: a
 * rep banked during it is shown as it is banked.
 *
 * Only what is drawn waits. The engine, the voice, the film and the session's record are fed from
 * the frame itself by the caller, and never from what this shows.
 */
class ScoreboardReadout(private val hud: ActivityMainBinding) {

    /** The figure, for the setup check and the finish, which write it directly. */
    val figure = ScoreboardFigure(hud.reps)

    private val line = ScoreLine(hud.movementLine)

    /** One set as the band reads it: "3/5" over "Pull-ups · Round 2". */
    private data class Set(val count: Int, val movement: Exercise, val round: Int)

    /** The engine's banked total the figure last showed, to tell a banked rep from a skip. */
    private var total = 0

    /** The set the engine is on, while the band holds another one on show; null while it holds none. */
    private var held: Set? = null

    private val clock = Handler(Looper.getMainLooper())
    private val showNext = Runnable { bringNextSet() }
    private val endNext = Runnable { release() }
    private var next: NextSet? = null

    /**
     * One frame of a live workout. [reps] is the movement's count now and [eventReps] the count
     * the movement had reached when [event] fired, which a finished set has already cleared.
     * [running] is whether the clock runs: only then is the athlete at the bar.
     */
    fun workout(
        movement: Exercise,
        reps: Int,
        rounds: Int,
        event: RepEvent,
        eventReps: Int,
        totalReps: Int,
        running: Boolean
    ) {
        val motion = FigureMotion.of(event, total, totalReps)
        total = totalReps
        val now = Set(reps, movement, rounds + 1)
        if (held != null) {
            // A state frame while the band holds: kept for when it lets go.
            if (event == RepEvent.NONE && running) {
                held = now
                return
            }
            release()
        }
        val coming = NextSet.after(event, motion, running, movement)
        if (coming == null) {
            draw(now, motion)
            return
        }
        // The set that was just left, as it stood when it was: its last rep, its round.
        val left = Set(
            eventReps,
            movement.previous(),
            if (event == RepEvent.ROUND_DONE) rounds else rounds + 1
        )
        draw(left, motion)
        held = now
        next = coming
        if (coming.inMs > 0) clock.postDelayed(showNext, coming.inMs) else bringNextSet()
    }

    /**
     * The clock has stopped, by a pause or the end: the athlete is at the phone, so a hold under
     * way ends at once and the band shows the set the engine is on.
     */
    fun clockStopped() = release()

    private fun bringNextSet() {
        val set = next ?: return
        hud.nextSetTarget.text = set.figure
        hud.nextSetMovement.text = set.name
        hud.nextSet.contentDescription = set.spoken
        hud.reps.visibility = View.INVISIBLE
        hud.movementLine.visibility = View.INVISIBLE
        hud.nextSet.visibility = View.VISIBLE
        hud.repProgress.progress = 0
        fadeIn()
        clock.postDelayed(endNext, NextSet.SHOWN_MS)
    }

    /**
     * The mock's 150 ms ease-out, up 8 dp from below and from clear to whole. With the system's
     * animations off it is simply there, and it always leaves at once.
     */
    private fun fadeIn() {
        val view = hud.nextSet
        view.animate().cancel()
        if (!ValueAnimator.areAnimatorsEnabled()) {
            view.alpha = 1f
            view.translationY = 0f
            return
        }
        view.alpha = 0f
        view.translationY = RISE_DP * view.resources.displayMetrics.density
        view.animate().alpha(1f).translationY(0f).setDuration(FADE_MS).setInterpolator(DecelerateInterpolator()).start()
    }

    /** Ends the hold, if there is one, and shows the set the engine is on. */
    private fun release() {
        clock.removeCallbacks(showNext)
        clock.removeCallbacks(endNext)
        next = null
        hud.nextSet.animate().cancel()
        hud.nextSet.alpha = 1f
        hud.nextSet.translationY = 0f
        hud.nextSet.visibility = View.GONE
        hud.reps.visibility = View.VISIBLE
        hud.movementLine.visibility = View.VISIBLE
        val set = held ?: return
        held = null
        draw(set, FigureMotion.NONE)
    }

    private fun draw(set: Set, motion: FigureMotion) {
        val target = set.movement.target
        line.show(set.movement.label, set.round)
        figure.show("${set.count}", "/$target", motion)
        figure.spoken("${set.count} of $target ${set.movement.label}")
        // Readable from the bar, when the digits are not.
        hud.repProgress.progress = set.count * 100 / target.coerceAtLeast(1)
    }

    /** The line under the figure, for the setup check, which names no movement. */
    fun line(movement: String) = line.show(movement, line.round)

    /**
     * The line under the figure, "Pull-ups · Round 2", written only when the movement or the
     * round changes. The movement is the engine's own label ("PULL-UPS"); only the line on the
     * screen is set in sentence case.
     */
    private class ScoreLine(private val view: TextView) {
        private var shown: String? = null
        private var spoken: String? = null
        var round: Int = 1
            private set

        fun show(movement: String, round: Int) {
            this.round = round
            val key = "$movement|$round"
            if (shown == key) return
            shown = key
            view.text = Scoreboard.line(movement, round)
            val say = Scoreboard.spokenLine(movement, round)
            if (spoken != say) {
                spoken = say
                view.contentDescription = say
            }
        }
    }

    private companion object {
        /** The mock's take-in (bands-two.js TIMING.takeIn), and how far up it comes. */
        const val FADE_MS = 150L
        const val RISE_DP = 8f
    }
}
