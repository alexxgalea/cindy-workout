package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PathEffect
import kotlin.math.hypot
import kotlin.math.min

/**
 * Draws the skeleton, and the pull-up bar zone when it is given one, onto a canvas that is
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
 * The film passes no bar zone, so what it burns in is the skeleton alone.
 */
class SkeletonPainter(
    private val boneColor: Int = FILM_BONE,
    private val zoneOkColor: Int = Color.GREEN,
    private val zoneAlertColor: Int = Color.RED,
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
    private val zoneFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val zoneEdge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val barLine = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val resetLine = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        style = Paint.Style.STROKE
        pathEffect = resetLinePathEffect
    }

    /** The bar zone goes under the skeleton, so the body is never obscured by its own gate. */
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

    private fun paintZone(canvas: Canvas, guide: WorkoutEngine.BarGuide, frameHeight: Int) {
        val rail = guide.rail
        if (rail != null) return paintRail(canvas, guide, rail, frameHeight)
        val z = guide.zone
        val colour = if (guide.gateOpen) zoneOkColor else zoneAlertColor
        zoneFill.color = colour
        zoneFill.alpha = ZONE_FILL_ALPHA
        canvas.drawRect(z.left, z.top, z.right, z.bottom, zoneFill)
        zoneEdge.color = colour
        zoneEdge.strokeWidth = frameHeight * ZONE_EDGE_FRACTION
        canvas.drawRect(z.left, z.top, z.right, z.bottom, zoneEdge)
        barLine.color = colour
        barLine.strokeWidth = frameHeight * BAR_WIDTH_FRACTION
        canvas.drawLine(z.left, z.lineY, z.right, z.lineY, barLine)
        // Where the head has to come back to before the next rep can arm.
        resetLine.strokeWidth = frameHeight * ZONE_EDGE_FRACTION
        canvas.drawLine(z.left, guide.resetY, z.right, guide.resetY, resetLine)
    }

    /** The bar where the picture has it: tilted, thin, in the gate's colour, with no box around it. */
    private fun paintRail(canvas: Canvas, guide: WorkoutEngine.BarGuide, rail: DrawnRail, h: Int) {
        val colour = if (guide.gateOpen) zoneOkColor else zoneAlertColor
        val t = h * RAIL_WIDTH_FRACTION
        val y0 = rail.line.yAt(rail.xFrom)
        val y1 = rail.line.yAt(rail.xTo)
        // A dark line just under it, so it reads against a white wall as well as a dark one.
        barLine.strokeWidth = t * 1.8f
        barLine.color = Color.argb(70, 0, 0, 0)
        canvas.drawLine(rail.xFrom, y0 + t * 0.5f, rail.xTo, y1 + t * 0.5f, barLine)
        barLine.strokeWidth = t
        barLine.color = colour
        canvas.drawLine(rail.xFrom, y0, rail.xTo, y1, barLine)
        // Where the head has to come back to before the next rep can arm.
        resetLine.strokeWidth = h * ZONE_EDGE_FRACTION
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

        /** The bar line, and the zone's outline, as a fraction of frame height. */
        const val BAR_WIDTH_FRACTION = 0.005f
        const val ZONE_EDGE_FRACTION = 0.002f

        /** The bar drawn on the real bar, as a fraction of frame height. */
        const val RAIL_WIDTH_FRACTION = 0.007f

        /** Alpha of the wash inside the bar zone: enough to read as a region, not as a mask. */
        const val ZONE_FILL_ALPHA = 26
    }
}
