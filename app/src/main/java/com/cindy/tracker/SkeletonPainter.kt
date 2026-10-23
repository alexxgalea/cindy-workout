package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PathEffect

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
        color = Color.WHITE
        style = Paint.Style.FILL
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
        val jointRadius = frameHeight * JOINT_RADIUS_FRACTION
        for ((a, b) in KP.SKELETON) {
            val pa = keypoints[a]
            val pb = keypoints[b]
            if (!PoseGeometry.ok(pa) || !PoseGeometry.ok(pb)) continue
            canvas.drawLine(pa.x, pa.y, pb.x, pb.y, bone)
        }
        for (p in keypoints) {
            if (!PoseGeometry.ok(p)) continue
            canvas.drawCircle(p.x, p.y, jointRadius, joint)
        }
    }

    private fun paintZone(canvas: Canvas, guide: WorkoutEngine.BarGuide, frameHeight: Int) {
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

    companion object {
        /** The film's bone colour: white, soft enough to follow the app's palette. */
        val FILM_BONE = Color.argb(168, 255, 255, 255)

        /**
         * Bone stroke width, as a fraction of frame height.
         *
         * Matches the live overlay's own weight: [OverlayView] draws 7 px bones and 9 px joint
         * radii in view pixels, which on its roughly 2.25x preview scale is about 3.1 and 4
         * analysis-frame pixels. The film used to draw 0.010 and 0.008 of the frame height
         * instead — about twice that — so the filmed skeleton read as heavier and less faithful
         * to the body than the one the athlete actually watched while training.
         */
        const val BONE_WIDTH_FRACTION = 0.0045f

        /** Joint radius, as a fraction of frame height. See [BONE_WIDTH_FRACTION]. */
        const val JOINT_RADIUS_FRACTION = 0.0055f

        /** The bar line, and the zone's outline, as a fraction of frame height. */
        const val BAR_WIDTH_FRACTION = 0.005f
        const val ZONE_EDGE_FRACTION = 0.002f

        /** Alpha of the wash inside the bar zone: enough to read as a region, not as a mask. */
        const val ZONE_FILL_ALPHA = 26
    }
}
