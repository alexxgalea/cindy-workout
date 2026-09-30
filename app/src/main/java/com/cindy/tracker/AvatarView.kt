package com.cindy.tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import androidx.core.content.res.ResourcesCompat

/**
 * The athlete, as a circle: their photo when they have given one, the letters of their name when
 * they have only given a name, and a neutral figure when they have given neither.
 *
 * One view is the whole avatar at every size, from the header of the menu to the top of the You
 * screen, and it stays monochrome. The palette keeps colour for what the athlete has earned, so
 * the letters and the figure are white ramp on the glass, and a photo brings its own colours.
 *
 * It only draws. A screen that makes it tappable names it to a screen reader itself, and the
 * rows that hold it already speak for their children.
 */
class AvatarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var photo: Bitmap? = null
    private var photoShader: BitmapShader? = null
    private var letters: String = ""

    private val disc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.surface_glass_raised)
    }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = context.getColor(R.color.hairline_strong)
        strokeWidth = context.hairlinePx().toFloat()
    }
    private val lettering = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.label)
        textAlign = Paint.Align.CENTER
        typeface = ResourcesCompat.getFont(context, R.font.manrope_extrabold)
    }
    private val figure = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = context.getColor(R.color.label_tertiary)
    }
    private val photoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private val clip = Path()
    private val oval = RectF()
    private val shaderMatrix = Matrix()

    init {
        // Decoration by default: a row that holds one already says what it is.
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    /** Shows [photo] if there is one, else the letters of [name], else a neutral figure. */
    fun show(photo: Bitmap?, name: String?) {
        this.photo = photo
        photoShader = photo?.let { BitmapShader(it, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        letters = Avatar.initials(name)
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val side = exactly(widthMeasureSpec) ?: exactly(heightMeasureSpec) ?: context.dp(DEFAULT_DP)
        setMeasuredDimension(side, side)
    }

    private fun exactly(spec: Int): Int? =
        if (MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY) MeasureSpec.getSize(spec) else null

    override fun onDraw(canvas: Canvas) {
        val side = minOf(width, height).toFloat()
        if (side <= 0f) return
        val cx = width / 2f
        val cy = height / 2f
        val radius = side / 2f

        val bitmap = photo
        val shader = photoShader
        if (bitmap != null && shader != null) {
            shaderMatrix.setScale(side / bitmap.width, side / bitmap.height)
            shaderMatrix.postTranslate(cx - radius, cy - radius)
            shader.setLocalMatrix(shaderMatrix)
            photoPaint.shader = shader
            canvas.drawCircle(cx, cy, radius, photoPaint)
        } else {
            canvas.drawCircle(cx, cy, radius, disc)
            if (letters.isNotEmpty()) drawLetters(canvas, cx, cy, side) else drawFigure(canvas, cx, cy, side)
        }
        // Drawn inside the edge, so the stroke is not half clipped away by the view's bounds.
        canvas.drawCircle(cx, cy, radius - ring.strokeWidth / 2f, ring)
    }

    private fun drawLetters(canvas: Canvas, cx: Float, cy: Float, side: Float) {
        val share = if (letters.length > 1) 0.36f else 0.42f
        lettering.textSize = side * share
        val metrics = lettering.fontMetrics
        canvas.drawText(letters, cx, cy - (metrics.ascent + metrics.descent) / 2f, lettering)
    }

    /** A head over a pair of shoulders, cut off by the disc: the sign for "somebody". */
    private fun drawFigure(canvas: Canvas, cx: Float, cy: Float, side: Float) {
        val left = cx - side / 2f
        val top = cy - side / 2f
        canvas.save()
        clip.reset()
        clip.addCircle(cx, cy, side / 2f, Path.Direction.CW)
        canvas.clipPath(clip)
        canvas.drawCircle(left + side * 0.5f, top + side * 0.38f, side * 0.17f, figure)
        oval.set(left + side * 0.20f, top + side * 0.62f, left + side * 0.80f, top + side * 1.10f)
        canvas.drawOval(oval, figure)
        canvas.restore()
    }

    private companion object {
        /** The size of a bare `wrap_content` avatar: the one in a row. */
        const val DEFAULT_DP = 44
    }
}
