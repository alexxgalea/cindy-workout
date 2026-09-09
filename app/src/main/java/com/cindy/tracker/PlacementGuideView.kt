package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * Where to stand, drawn rather than described.
 *
 * The setup check can already tell an athlete that something is wrong — "Can't see your ankles",
 * "Movement barely registers — raise the phone or step back" — but only once they are in front of
 * the camera getting it wrong. That is a slow way to learn a thing a picture settles in a second,
 * and it is worst for exactly the person least sure of what the app wants from them.
 *
 * A side elevation is the only view that carries the two facts that matter at once: how far back
 * to stand, and that the phone wants to be up off the floor. A photo of a room would carry
 * neither, because it would be *someone else's* room.
 *
 * ### Why 2–3 metres
 *
 * A phone in portrait sees roughly 60–65 degrees vertically. Fitting a 1.8 m athlete plus the
 * headroom a pull-up bar needs — call it 2.4 m of wall — puts the camera about
 * `1.2 / tan(31°) ≈ 2 m` away, and three gives margin for a taller athlete and a higher bar.
 * Deliberately a range, and deliberately confirmed by the setup check rather than trusted: the
 * exact field of view is a property of the handset, which this cannot know.
 */
class PlacementGuideView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        /** The floor, and everything else, as fractions of the view — so it scales anywhere. */
        const val GROUND = 0.78f
        const val PHONE_X = 0.09f
        const val LENS_Y = 0.435f
        const val ATHLETE_X = 0.66f
        const val DIMENSION_Y = 0.90f
    }

    private val density = resources.displayMetrics.density

    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 11f * density }

    private val accent = Color.parseColor("#00E5A0")
    private val dim = Color.parseColor("#99FFFFFF")
    private val faint = Color.parseColor("#59FFFFFF")

    private fun x(f: Float) = f * width
    private fun y(f: Float) = f * height

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return

        drawFloor(canvas)
        drawPhone(canvas)
        drawFieldOfView(canvas)
        drawAthlete(canvas)
        drawDistance(canvas)
    }

    private fun drawFloor(canvas: Canvas) {
        line.color = faint
        line.strokeWidth = 1.5f * density
        canvas.drawLine(x(0.04f), y(GROUND), x(0.97f), y(GROUND), line)
    }

    /** The phone, stood on something rather than lying on the floor. */
    private fun drawPhone(canvas: Canvas) {
        fill.color = Color.parseColor("#3CFFFFFF")
        canvas.drawRect(x(0.055f), y(0.68f), x(0.125f), y(GROUND), fill)

        fill.color = Color.parseColor("#E6FFFFFF")
        canvas.drawRoundRect(
            RectF(x(0.072f), y(0.40f), x(0.108f), y(0.68f)), 3f * density, 3f * density, fill
        )
        fill.color = Color.parseColor("#FF16191E")
        canvas.drawRect(x(0.076f), y(0.42f), x(0.104f), y(0.66f), fill)

        fill.color = accent
        canvas.drawCircle(x(PHONE_X), y(LENS_Y), 2.5f * density, fill)

        label.color = dim
        label.textAlign = Paint.Align.LEFT
        canvas.drawText("waist high or more", x(0.02f), y(0.36f), label)
    }

    /**
     * The two edges of what the camera sees.
     *
     * The lower edge stops where it meets the floor, because past that point the floor itself is
     * the bottom of the shot — drawing it on through the ground would say the opposite.
     */
    private fun drawFieldOfView(canvas: Canvas) {
        line.color = accent
        line.strokeWidth = 1f * density
        canvas.drawLine(x(PHONE_X), y(LENS_Y), x(0.823f), y(0.03f), line)
        canvas.drawLine(x(PHONE_X), y(LENS_Y), x(0.34f), y(GROUND), line)

        label.color = accent
        label.textAlign = Paint.Align.CENTER
        canvas.drawText("head and feet both in shot", x(0.60f), y(0.155f), label)
    }

    private fun drawAthlete(canvas: Canvas) {
        line.color = Color.WHITE
        line.strokeWidth = 2f * density
        val cx = x(ATHLETE_X)

        canvas.drawCircle(cx, y(0.22f), 0.047f * height, line)
        canvas.drawLine(cx, y(0.275f), cx, y(0.53f), line)
        canvas.drawLine(cx, y(0.31f), x(ATHLETE_X - 0.055f), y(0.45f), line)
        canvas.drawLine(cx, y(0.31f), x(ATHLETE_X + 0.055f), y(0.45f), line)
        canvas.drawLine(cx, y(0.53f), x(ATHLETE_X - 0.05f), y(GROUND), line)
        canvas.drawLine(cx, y(0.53f), x(ATHLETE_X + 0.05f), y(GROUND), line)
    }

    /** The dimension line: how far back to stand, with the figure that answers the question. */
    private fun drawDistance(canvas: Canvas) {
        line.color = faint
        line.strokeWidth = 1f * density
        canvas.drawLine(x(PHONE_X), y(GROUND + 0.02f), x(PHONE_X), y(DIMENSION_Y + 0.03f), line)
        canvas.drawLine(x(ATHLETE_X), y(GROUND + 0.02f), x(ATHLETE_X), y(DIMENSION_Y + 0.03f), line)

        line.color = dim
        line.strokeWidth = 1.5f * density
        arrow(canvas, from = 0.30f, to = PHONE_X)
        arrow(canvas, from = 0.45f, to = ATHLETE_X)

        label.color = Color.WHITE
        label.textSize = 13f * density
        label.textAlign = Paint.Align.CENTER
        canvas.drawText("2–3 m  ·  7–10 ft", x(0.375f), y(DIMENSION_Y + 0.02f), label)
        label.textSize = 11f * density
    }

    /** One half of the dimension line, with a head at the [to] end. */
    private fun arrow(canvas: Canvas, from: Float, to: Float) {
        val x0 = x(from)
        val x1 = x(to)
        val yy = y(DIMENSION_Y)
        canvas.drawLine(x0, yy, x1, yy, line)

        val head = 5f * density
        val angle = atan2(0f, x1 - x0)
        val path = Path()
        path.moveTo(x1, yy)
        path.lineTo(
            x1 - head * cos(angle - 0.4f).toFloat(), yy - head * sin(angle - 0.4f).toFloat()
        )
        path.moveTo(x1, yy)
        path.lineTo(
            x1 - head * cos(angle + 0.4f).toFloat(), yy - head * sin(angle + 0.4f).toFloat()
        )
        canvas.drawPath(path, line)
    }
}
