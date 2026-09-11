package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import androidx.core.content.res.ResourcesCompat
import kotlin.math.max
import kotlin.math.min

/**
 * The launch moment.
 *
 * It costs nothing. The window behind it is already black — `Theme.Cindy.Splash` paints the same
 * ground — and the time it fills is time the app was spending anyway: the TFLite interpreter is
 * being built and CameraX is warming up while this draws. [dismiss] is called when the preview
 * delivers its first frame, so the app is genuinely ready when the arcs go, rather than waiting
 * out a timer.
 *
 * This is emphatically not a home screen. Nothing here is tappable and nothing is waited on; the
 * app still opens straight to the camera, which is the whole reason it has no landing page.
 *
 * The mark is the workout: three arcs at 270°, 180° and 90° of a circle, which is fifteen squats,
 * ten push-ups and five pull-ups at their true proportion. They draw from the inside out — the
 * order the movements come in — and the innermost is brightest because it is the one you start on.
 */
class LaunchView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        /** Long enough that the mark is never a flash, short enough not to be a wait. */
        const val FLOOR_MS = 900L

        const val ARC_MS = 900f
        const val SWEEP_MS = 1400f

        /** Each arc waits for the one inside it to be under way. */
        val ARC_DELAYS = floatArrayOf(360f, 240f, 120f)
        val ARC_RADII = floatArrayOf(46f, 34f, 22f)
        val ARC_SWEEPS = floatArrayOf(270f, 180f, 90f)
        val ARC_ALPHAS = floatArrayOf(0.30f, 0.58f, 1f)

        const val WORDMARK_AT = 620f
        const val RULE_AT = 740f
        const val FOOT_AT = 980f
        const val RISE_MS = 700f
    }

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    private val wordmark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = ResourcesCompat.getFont(context, R.font.manrope_extrabold)
        textAlign = Paint.Align.CENTER
        letterSpacing = 0.1875f
    }
    private val eyebrow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = ResourcesCompat.getFont(context, R.font.manrope_bold)
        textAlign = Paint.Align.CENTER
        letterSpacing = 0.218f
    }
    private val foot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = ResourcesCompat.getFont(context, R.font.manrope_semibold)
        textAlign = Paint.Align.CENTER
        letterSpacing = 0.035f
    }

    private val oval = RectF()
    private val startedAt = System.currentTimeMillis()
    private var leaving = false

    init {
        setBackgroundResource(R.color.bg)
        isClickable = false
        // One node, so TalkBack says what the screen is instead of walking a canvas.
        contentDescription = "Cindy. AMRAP twenty minutes. Starting the camera."
    }

    /**
     * Fades out once the camera is live, but never before [FLOOR_MS] — a launch screen that
     * vanishes in 80ms on a warm start reads as a glitch rather than as an app opening.
     */
    fun dismiss(onDone: () -> Unit) {
        if (leaving) return
        leaving = true
        val waited = System.currentTimeMillis() - startedAt
        postDelayed({
            animate().alpha(0f).setDuration(340).withEndAction {
                visibility = GONE
                onDone()
            }.start()
        }, max(0L, FLOOR_MS - waited))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val t = (System.currentTimeMillis() - startedAt).toFloat()

        val cx = width / 2f
        // The block sits a little above centre; dead centre reads as low once the foot line is in.
        val markCy = height * 0.40f

        drawMark(canvas, cx, markCy, t)

        val wordY = markCy + dp(56f) + dp(34f)
        drawRising(canvas, t, WORDMARK_AT) { a, dy ->
            wordmark.textSize = dp(40f)
            wordmark.color = white(a)
            // letterSpacing pads the trailing glyph too, so nudge back by half of it to centre.
            canvas.drawText("CINDY", cx + dp(3.75f), wordY + dy, wordmark)
        }

        val ruleY = wordY + dp(30f)
        drawRising(canvas, t, RULE_AT) { a, dy ->
            eyebrow.textSize = dp(11f)
            eyebrow.color = white(a * 0.42f)
            canvas.drawText("AMRAP 20:00", cx + dp(1.2f), ruleY + dy + dp(4f), eyebrow)

            val half = eyebrow.measureText("AMRAP 20:00") / 2f
            stroke.color = white(a * 0.20f)
            stroke.strokeWidth = max(1f, dp(0.5f))
            val y = ruleY + dy
            canvas.drawLine(cx - half - dp(38f), y, cx - half - dp(12f), y, stroke)
            canvas.drawLine(cx + half + dp(12f), y, cx + half + dp(38f), y, stroke)
        }

        drawFoot(canvas, cx, t)

        if (!leaving || alpha > 0f) postInvalidateOnAnimation()
    }

    /** The three arcs, each sweeping on from twelve o'clock. */
    private fun drawMark(canvas: Canvas, cx: Float, cy: Float, t: Float) {
        stroke.strokeWidth = dp(5f)
        for (i in ARC_RADII.indices) {
            val r = dp(ARC_RADII[i])
            oval.set(cx - r, cy - r, cx + r, cy + r)

            stroke.color = white(0.06f)
            canvas.drawArc(oval, 0f, 360f, false, stroke)

            val p = ease(((t - ARC_DELAYS[i]) / ARC_MS).coerceIn(0f, 1f))
            if (p <= 0f) continue
            stroke.color = white(ARC_ALPHAS[i])
            canvas.drawArc(oval, -90f, ARC_SWEEPS[i] * p, false, stroke)
        }
    }

    /** The progress hairline, and what the workout actually is. */
    private fun drawFoot(canvas: Canvas, cx: Float, t: Float) {
        drawRising(canvas, t, FOOT_AT) { a, dy ->
            val trackW = dp(140f)
            val trackH = dp(3f)
            val trackY = height - dp(76f) - trackH + dy

            fill.color = white(a * 0.09f)
            canvas.drawRoundRect(
                cx - trackW / 2f, trackY, cx + trackW / 2f, trackY + trackH,
                trackH / 2f, trackH / 2f, fill
            )

            // Honest rather than decorative: real work is happening behind it.
            val segW = dp(46f)
            val u = ease2((t % SWEEP_MS) / SWEEP_MS)
            val left = cx - trackW / 2f - segW + u * (trackW + segW)
            canvas.save()
            canvas.clipRect(cx - trackW / 2f, trackY, cx + trackW / 2f, trackY + trackH)
            fill.color = white(a * 0.75f)
            canvas.drawRoundRect(
                left, trackY, left + segW, trackY + trackH, trackH / 2f, trackH / 2f, fill
            )
            canvas.restore()

            foot.textSize = dp(11.5f)
            foot.color = white(a * 0.34f)
            canvas.drawText(
                "5 pull-ups · 10 push-ups · 15 squats", cx, height - dp(36f) + dy, foot
            )
        }
    }

    /** Runs [body] with the fade and the few pixels of rise that every element shares. */
    private inline fun drawRising(canvas: Canvas, t: Float, at: Float, body: (Float, Float) -> Unit) {
        val p = ease(((t - at) / RISE_MS).coerceIn(0f, 1f))
        if (p <= 0f) return
        body(p, dp(9f) * (1f - p))
    }

    private fun ease(x: Float): Float {
        val c = x.coerceIn(0f, 1f)
        return 1f - (1f - c) * (1f - c) * (1f - c)
    }

    /** Symmetric ease, so the sweeping segment slows at both ends rather than only one. */
    private fun ease2(x: Float): Float {
        val c = x.coerceIn(0f, 1f)
        return c * c * (3f - 2f * c)
    }

    private fun white(a: Float): Int {
        val v = (max(0f, min(1f, a)) * 255f).toInt()
        return (v shl 24) or 0x00FFFFFF
    }
}
