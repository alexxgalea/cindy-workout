package com.cindy.tracker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The start-position demonstrator: a figure that walks into position and holds there.
 *
 * Shown when the athlete is in frame but the movement's own gate is shut — [WorkoutEngine.blocked]
 * with a hint that is not "Step into frame". That state was already computed and already had a
 * sentence attached to it ([Exercise.startCue], whose comment says it is "said and shown"); this
 * is the shown half, which had never been built.
 *
 * ### The rotation
 *
 * [StartPoses] stores a z for every joint, so this is a genuine turn rather than a wobble: the
 * pose is rotated about the vertical axis through the figure and projected with a weak
 * perspective. Depth then falls out of it for free — each bone's alpha and stroke width follow
 * its rotated z, so a limb swinging behind the body dims and thins on its own. That is the whole
 * three-dimensional cue; there is no mesh, no model and no renderer beyond [Canvas].
 *
 * ### The loop
 *
 * Poses are interpolated rather than cut, and the target is held for over half the cycle — the
 * two approach frames exist only to say which way to move, so lingering on them would be
 * lingering on the wrong thing. The rewind fades rather than snapping.
 */
class StartPoseView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : View(context, attrs, defStyle) {

    private companion object {
        const val LOOP_MS = 4000f
        const val YAW_MS = 5400f
        const val YAW_DEGREES = 15f

        /** Fractions of the loop: reach, settle, hold, rewind. */
        const val REACH_END = 0.22f
        const val SETTLE_END = 0.46f
        const val HOLD_END = 0.88f

        /** Large enough that the perspective reads as depth rather than as a fish-eye. */
        const val FOCAL = 620f
    }

    private val density = resources.displayMetrics.density

    private val bone = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val torso = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val path = Path()

    private var loop: StartPoses.Loop? = null
    private var startedAt = 0L

    /** Scratch, so a frame allocates nothing. */
    private val blended = FloatArray(StartPoses.JOINTS * 3)
    private val screenX = FloatArray(StartPoses.JOINTS)
    private val screenY = FloatArray(StartPoses.JOINTS)
    private val screenZ = FloatArray(StartPoses.JOINTS)

    /**
     * Bone indices re-sorted back to front each frame, and their depths.
     *
     * Preallocated because this runs at frame rate on the camera screen, where the analysis loop
     * is already the busiest thing on the device. `sortedBy` would allocate a boxed list and a
     * comparator every draw.
     */
    private val boneOrder = IntArray(StartPoses.BONES.size) { it }
    private val boneDepth = FloatArray(StartPoses.BONES.size)

    /** The movement being demonstrated. Setting the same one twice does not restart the loop. */
    fun show(exercise: Exercise) {
        val next = StartPoses.of(exercise)
        if (next === loop) return
        loop = next
        startedAt = System.currentTimeMillis()
        invalidate()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        // Restarted from the top so it never appears mid-rewind.
        if (visibility == VISIBLE) {
            startedAt = System.currentTimeMillis()
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val l = loop ?: return
        if (width == 0 || height == 0) return

        val now = System.currentTimeMillis()
        if (startedAt == 0L) startedAt = now
        val elapsed = (now - startedAt).toFloat()

        val t = (elapsed % LOOP_MS) / LOOP_MS
        val yaw = sin(elapsed / YAW_MS * 2.0 * Math.PI).toFloat() * YAW_DEGREES

        val alpha = blend(l, t)
        project(l, yaw)
        draw(canvas, l, alpha)

        // Time-based, so a dropped frame changes nothing about where the loop is.
        postInvalidateOnAnimation()
    }

    /**
     * Fills [blended] for the loop position [t], and returns the figure's overall alpha.
     *
     * The rewind is the only part that fades: cutting from the held position back to the
     * approach reads as a glitch, whereas dipping through it reads as starting over.
     */
    private fun blend(l: StartPoses.Loop, t: Float): Float {
        val f = l.frames
        return when {
            t < REACH_END -> {
                lerpInto(f[0], f[1], ease(t / REACH_END)); 1f
            }
            t < SETTLE_END -> {
                lerpInto(f[1], f[2], ease((t - REACH_END) / (SETTLE_END - REACH_END))); 1f
            }
            t < HOLD_END -> {
                lerpInto(f[2], f[2], 0f); 1f
            }
            else -> {
                val u = (t - HOLD_END) / (1f - HOLD_END)
                lerpInto(f[2], f[0], ease(u))
                // Dips to a quarter at the halfway point of the rewind, then back.
                0.25f + 0.75f * (2f * u - 1f) * (2f * u - 1f)
            }
        }
    }

    private fun ease(x: Float): Float {
        val c = x.coerceIn(0f, 1f)
        return c * c * (3f - 2f * c)
    }

    private fun lerpInto(a: FloatArray, b: FloatArray, u: Float) {
        for (i in blended.indices) blended[i] = a[i] + (b[i] - a[i]) * u
    }

    /** Rotates about the figure's own vertical axis and projects into view pixels. */
    private fun project(l: StartPoses.Loop, yawDegrees: Float) {
        val scale = min(width / l.boxWidth, height / l.boxHeight)
        val offsetX = (width - l.boxWidth * scale) / 2f
        val offsetY = (height - l.boxHeight * scale) / 2f

        val cx = l.boxWidth / 2f
        val cy = l.boxHeight / 2f
        val a = Math.toRadians(yawDegrees.toDouble())
        val cosA = cos(a).toFloat()
        val sinA = sin(a).toFloat()

        for (j in 0 until StartPoses.JOINTS) {
            val x = blended[j * 3]
            val y = blended[j * 3 + 1]
            val z = blended[j * 3 + 2]

            val dx = x - cx
            val rx = dx * cosA + z * sinA
            val rz = -dx * sinA + z * cosA

            // Weak perspective: nearer joints grow a little, which is what sells the turn.
            val p = FOCAL / (FOCAL - rz)
            screenX[j] = offsetX + (cx + rx * p) * scale
            screenY[j] = offsetY + (cy + (y - cy) * p) * scale
            screenZ[j] = rz
        }
    }

    private fun draw(canvas: Canvas, l: StartPoses.Loop, alpha: Float) {
        val scale = min(width / l.boxWidth, height / l.boxHeight)
        val offsetX = (width - l.boxWidth * scale) / 2f
        val offsetY = (height - l.boxHeight * scale) / 2f

        // The bar, where there is one to hang from.
        l.barY?.let { barY ->
            bone.color = white(0.34f * alpha)
            bone.strokeWidth = 5f * scale
            val y = offsetY + barY * scale
            canvas.drawLine(offsetX + 14f * scale, y, offsetX + (l.boxWidth - 14f) * scale, y, bone)
        }

        // A soft contact shadow, so the figure stands on something.
        val footX = (screenX[StartPoses.L_ANKLE] + screenX[StartPoses.R_ANKLE]) / 2f
        fill.color = white(0.07f * alpha)
        canvas.drawOval(
            footX - 26f * scale, offsetY + (l.groundY - 2f) * scale,
            footX + 26f * scale, offsetY + (l.groundY + 5f) * scale, fill
        )

        // Torso as a quad, so the body has a mass rather than being four sticks.
        path.reset()
        path.moveTo(screenX[StartPoses.L_SHOULDER], screenY[StartPoses.L_SHOULDER])
        path.lineTo(screenX[StartPoses.R_SHOULDER], screenY[StartPoses.R_SHOULDER])
        path.lineTo(screenX[StartPoses.R_HIP], screenY[StartPoses.R_HIP])
        path.lineTo(screenX[StartPoses.L_HIP], screenY[StartPoses.L_HIP])
        path.close()
        torso.color = white(0.09f * alpha)
        canvas.drawPath(path, torso)

        // Back to front, so a near limb crosses over a far one rather than under it.
        sortBonesByDepth()
        for (i in boneOrder) {
            val b = StartPoses.BONES[i]
            val depth = (screenZ[b[0]] + screenZ[b[1]]) / 2f
            bone.color = white(depthAlpha(depth) * alpha)
            bone.strokeWidth = (2.4f + 0.9f * depthUnit(depth)) * scale
            canvas.drawLine(screenX[b[0]], screenY[b[0]], screenX[b[1]], screenY[b[1]], bone)
        }

        // Joints on the near side only; dotting all thirteen turns the figure into a constellation.
        fill.color = white(0.95f * alpha)
        for (j in intArrayOf(
            StartPoses.R_SHOULDER, StartPoses.R_ELBOW, StartPoses.R_WRIST,
            StartPoses.R_HIP, StartPoses.R_KNEE, StartPoses.R_ANKLE
        )) {
            canvas.drawCircle(screenX[j], screenY[j], 2.6f * scale, fill)
        }

        bone.color = white(0.98f * alpha)
        bone.strokeWidth = 3f * scale
        canvas.drawCircle(
            screenX[StartPoses.NOSE], screenY[StartPoses.NOSE], l.headRadius * scale, bone
        )
    }

    /** Orders [boneOrder] furthest-first, in place. Twelve elements, so an insertion sort. */
    private fun sortBonesByDepth() {
        for (i in StartPoses.BONES.indices) {
            val b = StartPoses.BONES[i]
            boneDepth[i] = (screenZ[b[0]] + screenZ[b[1]]) / 2f
            boneOrder[i] = i
        }
        for (i in 1 until boneOrder.size) {
            val v = boneOrder[i]
            var j = i - 1
            while (j >= 0 && boneDepth[boneOrder[j]] > boneDepth[v]) {
                boneOrder[j + 1] = boneOrder[j]
                j--
            }
            boneOrder[j + 1] = v
        }
    }

    /** Nearer bones are brighter. The span is deliberately wide, because it is the only depth cue. */
    private fun depthAlpha(z: Float): Float = 0.30f + 0.70f * depthUnit(z)

    /** Maps a rotated z onto 0 (furthest) to 1 (nearest). */
    private fun depthUnit(z: Float): Float = ((z + 9f) / 18f).coerceIn(0f, 1f)

    private fun white(a: Float): Int {
        val v = (max(0f, min(1f, a)) * 255f).toInt()
        return (v shl 24) or 0x00FFFFFF
    }
}
