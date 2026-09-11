package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import androidx.core.content.res.ResourcesCompat
import kotlin.math.ceil
import kotlin.math.min

/**
 * The three seconds between tapping REC and the camera actually rolling.
 *
 * Recording used to begin on the down-stroke of the tap, which meant every clip opened on the
 * athlete's arm coming back from the phone and them walking to the bar — and, worse, gave no
 * warning at all that filming had begun. A countdown is the one piece of a camera app this HUD
 * was missing: it is both a promise that the recording is coming and the time to get into the
 * shot before it does.
 *
 * It draws over the picture and not in a band, because it is the only thing on the screen for
 * the length of it — but it does **not** dim the frame. The bright middle is the framing zone
 * (see the layout's comment), and an athlete who cannot see themselves during the three seconds
 * they have to get placed is worse off than one reading a slightly lower-contrast digit. The
 * legibility comes from a vignette behind the ring instead, which darkens the middle of the
 * picture and leaves its edges — where the body is being judged — alone.
 *
 * The clock is [SystemClock.uptimeMillis], the same base [Handler.postDelayed] schedules on, so
 * the digit and the callback cannot disagree about when a second passed.
 */
class CountdownView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private companion object {
        /** Long enough to put the phone down and turn round; short enough not to be a wait. */
        const val DEFAULT_SECONDS = 3
        const val FRAME_MS = 16L
        const val RING_DP = 58f
        const val STROKE_DP = 3.5f
    }

    private val ui = Handler(Looper.getMainLooper())
    private var endAt = 0L
    private var onFinished: (() -> Unit)? = null

    /** True between [start] and the moment the callback fires, or [cancel]. */
    val isRunning: Boolean get() = onFinished != null

    private val ring = RectF()
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = context.getColor(R.color.hairline_strong)
    }
    private val sweepPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = context.getColor(R.color.state_alert)
    }
    private val vignettePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val digitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        color = context.getColor(R.color.label)
        typeface = ResourcesCompat.getFont(context, R.font.manrope_extrabold)
        // Manrope's figures are proportional, so a 3 and a 1 sit at different widths without it.
        fontFeatureSettings = "tnum"
    }
    private val captionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        color = context.getColor(R.color.state_alert)
        typeface = ResourcesCompat.getFont(context, R.font.manrope_extrabold)
        letterSpacing = 0.14f
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.state_alert)
    }

    private val frame = object : Runnable {
        override fun run() {
            if (!isRunning) return
            if (SystemClock.uptimeMillis() >= endAt) {
                finish()
                return
            }
            invalidate()
            ui.postDelayed(this, FRAME_MS)
        }
    }

    /**
     * Counts [fromSeconds] down and then calls [onFinished] exactly once.
     *
     * Starting a countdown that is already running restarts it, which is what a second tap on a
     * control that has no other meaning should do — though [MainActivity] gives the second tap
     * to cancelling instead, since a countdown you cannot call off is a recording you cannot
     * refuse.
     */
    fun start(fromSeconds: Int = DEFAULT_SECONDS, onFinished: () -> Unit) {
        cancel()
        val seconds = fromSeconds.coerceAtLeast(1)
        endAt = SystemClock.uptimeMillis() + seconds * 1000L
        this.onFinished = onFinished
        visibility = VISIBLE
        // The digits are drawn on a canvas, so this is all a screen reader will ever get.
        contentDescription = "Recording starts in $seconds seconds"
        announceForAccessibility("Recording in $seconds")
        invalidate()
        ui.post(frame)
    }

    /** Calls the countdown off. The callback does not run. */
    fun cancel() = stop()

    private fun finish() {
        val done = onFinished
        stop()
        done?.invoke()
    }

    private fun stop() {
        ui.removeCallbacks(frame)
        onFinished = null
        visibility = GONE
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val radius = context.dpf(RING_DP)
        val cx = w / 2f
        val cy = h / 2f
        ring.set(cx - radius, cy - radius, cx + radius, cy + radius)
        trackPaint.strokeWidth = context.dpf(STROKE_DP)
        sweepPaint.strokeWidth = context.dpf(STROKE_DP)
        digitPaint.textSize = context.dpf(64f)
        captionPaint.textSize = context.dpf(11f)
        vignettePaint.shader = RadialGradient(
            cx, cy, radius * 2.6f,
            intArrayOf(0xC4000000.toInt(), 0x8A000000.toInt(), Color.TRANSPARENT),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        if (!isRunning) return
        val left = (endAt - SystemClock.uptimeMillis()).coerceAtLeast(0L)
        // 3000ms left is "3", and the digit only becomes "2" once the third second is spent.
        val digit = ceil(left / 1000.0).toInt().coerceAtLeast(1)
        // 0 on the digit's first frame, 1 on its last.
        val into = 1f - (left - (digit - 1) * 1000L) / 1000f

        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), vignettePaint)
        canvas.drawOval(ring, trackPaint)
        // Drains clockwise from twelve o'clock, so what is left of the ring is what is left of
        // the second.
        canvas.drawArc(ring, -90f, 360f * (1f - into), false, sweepPaint)

        // Each digit arrives a little oversized and settles, which reads as a beat rather than a
        // number being replaced.
        val pop = 1f + 0.16f * (1f - min(1f, into * 5f))
        digitPaint.alpha = (255 * min(1f, 0.35f + into * 6f)).toInt()
        canvas.save()
        canvas.scale(pop, pop, ring.centerX(), ring.centerY())
        // Centred on the ring by cap height rather than by baseline, or it hangs low in the ring.
        val metrics = digitPaint.fontMetrics
        val baseline = ring.centerY() - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(digit.toString(), ring.centerX(), baseline, digitPaint)
        canvas.restore()

        val captionY = ring.bottom + context.dpf(30f)
        val caption = "RECORDING"
        val dotGap = context.dpf(7f)
        val dotRadius = context.dpf(3.5f)
        val textWidth = captionPaint.measureText(caption)
        val start = ring.centerX() - (textWidth + dotGap + dotRadius * 2) / 2f
        canvas.drawCircle(start + dotRadius, captionY - captionPaint.textSize / 3f, dotRadius, dotPaint)
        canvas.drawText(
            caption,
            start + dotRadius * 2 + dotGap + textWidth / 2f,
            captionY,
            captionPaint
        )
    }
}
