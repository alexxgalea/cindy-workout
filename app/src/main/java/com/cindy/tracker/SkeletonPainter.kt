package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PathEffect
import kotlin.math.hypot
import kotlin.math.min

/**
 * Draws the skeleton, and the pull-up bar when it is given one, onto a canvas that is
 * already mapped to the analysed frame.
 *
 * Everything is in the frame's own coordinates, the space the keypoints arrive in, so the caller
 * owns the mapping to wherever the picture really is, and this owns what is drawn. Line weights
 * are a fraction of [frameHeight] so they survive that mapping at any scale.
 *
 * Which joints count as seen is [PoseGeometry.MIN_SCORE], the engine's own threshold: a joint
 * under it is skipped, and so is every bone touching it.
 *
 * ### A quiet skeleton
 *
 * The skeleton is there to be checked against the body, not to cover it. So a bone is a thin line
 * that stops short of each joint, and a joint is a hollow ring: the athlete's own shoulders,
 * elbows and knees stay visible through it. The face gets nothing, because [FIRST_BODY_JOINT]
 * starts below it; the nose, eyes and ears still feed the engine, they are only not drawn.
 *
 * The film passes no bar, so what it burns in is the skeleton alone.
 */
class SkeletonPainter(
    private val boneColor: Int = FILM_BONE,
    resetLinePathEffect: PathEffect? = null
) {
    private val bone = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = boneColor
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val joint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = boneColor
        style = Paint.Style.STROKE
    }
    private val barLine = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = boneColor
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val resetLine = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        style = Paint.Style.STROKE
        pathEffect = resetLinePathEffect
    }

    /** The bar goes under the skeleton, so the body is never obscured by its own gate. */
    fun paint(
        canvas: Canvas,
        keypoints: Array<Keypoint>,
        frameHeight: Int,
        guide: WorkoutEngine.BarGuide? = null
    ) {
        if (guide != null) paintZone(canvas, guide, frameHeight)
        paintBody(canvas, keypoints, frameHeight)
    }

    private fun paintBody(canvas: Canvas, keypoints: Array<Keypoint>, frameHeight: Int) {
        bone.strokeWidth = frameHeight * BONE_WIDTH_FRACTION
        val gap = frameHeight * BONE_GAP_FRACTION
        for ((a, b) in KP.SKELETON) {
            val pa = keypoints[a]
            val pb = keypoints[b]
            if (!PoseGeometry.ok(pa) || !PoseGeometry.ok(pb)) continue
            val dx = pb.x - pa.x
            val dy = pb.y - pa.y
            val length = hypot(dx, dy)
            if (length <= 0f) continue
            // A body seen from far away has bones shorter than two gaps: trim those in proportion.
            val trim = min(gap, length * MAX_GAP_SHARE) / length
            canvas.drawLine(
                pa.x + dx * trim, pa.y + dy * trim,
                pb.x - dx * trim, pb.y - dy * trim,
                bone
            )
        }
        joint.strokeWidth = frameHeight * JOINT_STROKE_FRACTION
        val jointRadius = frameHeight * JOINT_RADIUS_FRACTION
        for (i in FIRST_BODY_JOINT until KP.COUNT) {
            val p = keypoints[i]
            if (!PoseGeometry.ok(p)) continue
            canvas.drawCircle(p.x, p.y, jointRadius, joint)
        }
    }

    /**
     * The bar where the picture has it: tilted, thin, and the skeleton's own colour. Nothing is
     * drawn until the bar has been seen; the old gate's box and level line are gone.
     */
    private fun paintZone(canvas: Canvas, guide: WorkoutEngine.BarGuide, h: Int) {
        val rail = guide.rail ?: return
        barLine.strokeWidth = h * RAIL_WIDTH_FRACTION
        canvas.drawLine(
            rail.xFrom, rail.line.yAt(rail.xFrom),
            rail.xTo, rail.line.yAt(rail.xTo),
            barLine
        )
        // Where the head has to come back to before the next rep can arm.
        resetLine.strokeWidth = h * RESET_WIDTH_FRACTION
        canvas.drawLine(rail.xFrom, guide.resetY, rail.xTo, guide.resetY, resetLine)
    }

    companion object {
        /**
         * The film's bone colour: the app's skeleton cyan, `R.color.skeleton`, at 80%. It is spelled
         * out here because the film's painter is built without a [android.content.Context]; the
         * screen passes the resource itself.
         */
        val FILM_BONE = Color.argb(204, 100, 210, 255)

        /** The first keypoint that is drawn. Those before it are the face: nose, eyes, ears. */
        const val FIRST_BODY_JOINT = KP.LEFT_SHOULDER

        /**
         * Bone stroke width, as a fraction of frame height.
         *
         * Every width here is a fraction of the frame so one look survives any mapping. On the
         * screen's roughly 2.25x preview scale this bone is about 1.6 dp.
         */
        const val BONE_WIDTH_FRACTION = 0.0033f

        /** The ring around a joint: its radius, and the width of its line. */
        const val JOINT_RADIUS_FRACTION = 0.0067f
        const val JOINT_STROKE_FRACTION = 0.0029f

        /**
         * How far a bone stops short of each joint, as a fraction of frame height. Larger than a
         * ring's outer edge ([JOINT_RADIUS_FRACTION] plus half [JOINT_STROKE_FRACTION]), so ring
         * and bone never touch and the body shows between them.
         */
        const val BONE_GAP_FRACTION = 0.0146f

        /** A bone is never trimmed by more than this share of its length at each end. */
        const val MAX_GAP_SHARE = 0.3f

        /** The bar drawn on the real bar, as a fraction of frame height: thinner than a bone. */
        const val RAIL_WIDTH_FRACTION = 0.0025f

        /** The head's return line, as a fraction of frame height. */
        const val RESET_WIDTH_FRACTION = 0.002f
    }
}
