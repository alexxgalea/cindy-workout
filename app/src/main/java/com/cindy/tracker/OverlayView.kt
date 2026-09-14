package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.max

/**
 * Draws the detected skeleton, and the pull-up gate, on top of the preview.
 *
 * Keypoints arrive in analysis-frame pixels, which is a different resolution to the view, so
 * the same FILL_CENTER mapping PreviewView applies is recomputed here — otherwise the skeleton
 * drifts away from the body on any device whose preview and analysis aspect ratios differ.
 *
 * ### This view is fed from the analysis thread, on purpose
 *
 * Poses are handed straight to [submit] by the analysis thread rather than routed through a
 * `post` to the main thread. A posted runnable is a queue, and a queue with no back-pressure
 * turns a fixed lag into a growing one the moment the main thread falls behind: every pose ever
 * computed eventually gets drawn, each one older than the last. Here the newest pose simply
 * replaces the one before it, so a busy main thread costs frames rather than freshness — which
 * is the same bargain `STRATEGY_KEEP_ONLY_LATEST` already makes upstream.
 */
class OverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        const val MIN_SCORE = 0.30f
        /** Alpha of the wash inside the bar zone: enough to read as a region, not as a mask. */
        const val ZONE_FILL_ALPHA = 26

        /** Stop asking for frames once the pose stream has gone this quiet. */
        const val IDLE_STOP_MS = 1_000L
        /** Below this much movement, in frame pixels, another frame would redraw the same thing. */
        const val STILL_PX = 0.5f
    }

    /** One analysed frame, immutable so the analysis thread can publish it without a lock. */
    private class PoseFrame(
        val keypoints: Array<Keypoint>,
        val srcW: Int,
        val srcH: Int,
        val guide: WorkoutEngine.BarGuide?,
        val nanos: Long,
        /** How old this pose already was when it was published — the pipeline's own lag. */
        val pipelineAgeMs: Float
    )

    /** Newest last, at most three — the third is what makes a direction change detectable. */
    @Volatile
    private var frames: List<PoseFrame> = emptyList()

    /**
     * Whether the skeleton may be drawn ahead of the last pose.
     *
     * Off by default and deliberately a switch rather than a decision: it is the one display
     * change that can put a joint somewhere the body never was, and the only honest way to judge
     * that is on a phone, at the top of a pull-up, with it flipped on and off.
     */
    @Volatile
    var predict: Boolean = false
        set(value) {
            field = value
            postInvalidateOnAnimation()
        }

    /** Draw rate, for the latency readout. Counted here because this is what the athlete sees. */
    val drawRate = RateMeter()

    // The gate's two states, and nothing else on this canvas is coloured. The skeleton used to
    // be drawn in the accent — the same colour as titles, chips, streaks and scores — so seeing
    // green on screen told the athlete nothing at all. Now it means one thing: this would count.
    private val ok = ContextCompat.getColor(context, R.color.state_ok)
    private val alert = ContextCompat.getColor(context, R.color.state_alert)

    private val bonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.label)
        strokeWidth = 7f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val jointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val zonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeWidth = 3f
        style = Paint.Style.STROKE
    }
    private val zoneFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeWidth = 8f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    private val resetPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.label_secondary)
        strokeWidth = 3f
        style = Paint.Style.STROKE
        pathEffect = DashPathEffect(floatArrayOf(18f, 14f), 0f)
    }

    /** Scratch for the drawn pose, so a 60Hz redraw allocates nothing. */
    private val drawn = FloatArray(KP.COUNT * 2)
    /** What was on screen last frame, to notice when another frame would change nothing. */
    private val lastDrawn = FloatArray(KP.COUNT * 2)

    /**
     * Publishes one analysed frame. [guide] is the pull-up gate, or null for the movements and
     * the moments that have no bar to show. Called from the analysis thread.
     *
     * [nanos] is [System.nanoTime] taken when the frame was analysed, not the sensor's capture
     * stamp — the pose timeline only needs to be self-consistent to yield a velocity, and
     * borrowing the camera's clock would drag its whole domain problem (see [FrameLatency]) into
     * the render path.
     *
     * [pipelineAgeMs] is the part that stamp cannot supply: how far behind the body this pose
     * already was the moment it arrived. Velocity comes from the stamps, the horizon comes from
     * this, and conflating the two is what made the first version of prediction useless.
     */
    fun submit(
        keypoints: Array<Keypoint>?,
        sourceWidth: Int,
        sourceHeight: Int,
        guide: WorkoutEngine.BarGuide? = null,
        pipelineAgeMs: Float = 0f,
        nanos: Long = System.nanoTime()
    ) {
        frames = if (keypoints == null) {
            emptyList()
        } else {
            val frame = PoseFrame(keypoints, sourceWidth, sourceHeight, guide, nanos, pipelineAgeMs)
            (frames + frame).takeLast(3)
        }
        postInvalidateOnAnimation()
    }

    fun clear() = submit(null, 0, 0, null)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val history = frames
        val newest = history.lastOrNull() ?: return
        if (newest.srcW == 0 || newest.srcH == 0) return

        drawRate.mark()

        // FILL_CENTER: scale up until both axes are covered, then centre the overflow.
        val scale = max(width.toFloat() / newest.srcW, height.toFloat() / newest.srcH)
        val dx = (width - newest.srcW * scale) / 2f
        val dy = (height - newest.srcH * scale) / 2f

        fun sx(x: Float) = x * scale + dx
        fun sy(y: Float) = y * scale + dy

        // Under the skeleton, so the body is never obscured by its own gate. The gate is a
        // learned position in frame pixels, not something the body is doing, so it is never
        // predicted — only the skeleton moves.
        newest.guide?.let { guide ->
            val colour = if (guide.gateOpen) ok else alert
            val left = sx(guide.zone.left)
            val right = sx(guide.zone.right)
            zoneFillPaint.color = colour
            zoneFillPaint.alpha = ZONE_FILL_ALPHA
            canvas.drawRect(left, sy(guide.zone.top), right, sy(guide.zone.bottom), zoneFillPaint)
            zonePaint.color = colour
            canvas.drawRect(left, sy(guide.zone.top), right, sy(guide.zone.bottom), zonePaint)
            barPaint.color = colour
            canvas.drawLine(left, sy(guide.zone.lineY), right, sy(guide.zone.lineY), barPaint)
            // Where the head has to come back to before the next rep can arm.
            canvas.drawLine(left, sy(guide.resetY), right, sy(guide.resetY), resetPaint)
        }

        val now = System.nanoTime()
        resolvePositions(history, now)

        val k = newest.keypoints
        for ((a, b) in KP.SKELETON) {
            if (k[a].score < MIN_SCORE || k[b].score < MIN_SCORE) continue
            canvas.drawLine(
                sx(drawn[a * 2]), sy(drawn[a * 2 + 1]),
                sx(drawn[b * 2]), sy(drawn[b * 2 + 1]),
                bonePaint
            )
        }
        for (i in 0 until KP.COUNT) {
            if (k[i].score < MIN_SCORE) continue
            canvas.drawCircle(sx(drawn[i * 2]), sy(drawn[i * 2 + 1]), 9f, jointPaint)
        }

        // Predicting only pays if the picture is refreshed between poses, so this is the one mode
        // that asks for frames of its own. Two things stop it asking, because those frames are not
        // free — measured at about 18% of the analysis rate on the test handset, which is a tax
        // paid in exactly the currency prediction is trying to buy:
        //
        //  - the pose stream has gone quiet, so the workout is over or paused;
        //  - nothing moved, so the next frame would redraw this one. An athlete resting between
        //    rounds is perfectly still for seconds at a time, and there is no reason to hold the
        //    compositor open through it. A new pose always invalidates, so this cannot stick.
        val moved = maxMovement()
        System.arraycopy(drawn, 0, lastDrawn, 0, drawn.size)
        if (predict && moved >= STILL_PX && (now - newest.nanos) / 1_000_000L < IDLE_STOP_MS) {
            postInvalidateOnAnimation()
        }
    }

    /** The furthest any joint travelled since the last draw, in frame pixels. */
    private fun maxMovement(): Float {
        var most = 0f
        for (i in drawn.indices) most = max(most, abs(drawn[i] - lastDrawn[i]))
        return most
    }

    /**
     * Fills [drawn] with where each joint should appear right now.
     *
     * With prediction off, or before three poses have arrived, this is simply the newest pose.
     * The bounded carry-forward and the reasoning behind every bound live in [PosePrediction],
     * which is pure so it can be tested without a screen.
     */
    private fun resolvePositions(history: List<PoseFrame>, now: Long) {
        val newest = history.last()
        val usable = predict && history.size >= 3
        PosePrediction.resolve(
            newest = newest.keypoints,
            newestNanos = newest.nanos,
            previous = if (usable) history[1].keypoints else null,
            previousNanos = if (usable) history[1].nanos else 0L,
            oldest = if (usable) history[0].keypoints else null,
            oldestNanos = if (usable) history[0].nanos else 0L,
            nowNanos = now,
            pipelineAgeMs = newest.pipelineAgeMs,
            out = drawn
        )
    }
}
