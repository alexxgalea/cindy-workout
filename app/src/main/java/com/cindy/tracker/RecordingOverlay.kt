package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.RectF
import androidx.camera.effects.Frame

/**
 * Burns the skeleton, the score and a watermark into the recorded video.
 *
 * The preview's overlay is a separate view drawn on top of the screen; it never reaches the
 * encoder. CameraX's `OverlayEffect` hands us a canvas over the *recorded* buffer instead, so
 * whatever is drawn here is in the file.
 *
 * ### Coordinates
 *
 * Everything is drawn in the analysis frame's upright space — the same space the keypoints and
 * the on-screen overlay already use — and mapped to the video buffer with one matrix composed
 * from each frame's own metadata. Going through the sensor like this means the two streams may
 * differ in resolution, crop, rotation or mirroring and the skeleton still lands on the body.
 * Drawing the text through the same matrix is what keeps it the right way up.
 *
 * ### Mirroring
 *
 * The skeleton and the HUD do not want the same matrix. The selfie camera's keypoints are
 * mirrored while its recorded buffer is not, so the skeleton has to be flipped back to land on
 * the body — but a flipped canvas also writes every letter backwards, which is how the recording
 * ended up with a reversed clock, round and rep count. So the body is drawn through the
 * mirror-corrected matrix and the HUD through the plain one.
 */
class RecordingOverlay {

    private data class State(
        val keypoints: Array<Keypoint>,
        val width: Int,
        val height: Int,
        /** Whether the analysis frame was mirrored, as it is for the selfie camera. */
        val mirrored: Boolean,
        val clock: String,
        val round: String,
        val exercise: String,
        val reps: String,
        val debug: Boolean
    )

    @Volatile
    private var state: State? = null

    private val bone = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val joint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val panel = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 0, 0, 0)
        style = Paint.Style.FILL
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        isFakeBoldText = true
    }
    private val accentText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT
        isFakeBoldText = true
    }
    private val mark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT
        isFakeBoldText = true
        textAlign = Paint.Align.RIGHT
    }
    private val markSub = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        textAlign = Paint.Align.RIGHT
    }

    /** Called from the analysis thread with everything the next drawn frame should show. */
    fun update(
        keypoints: Array<Keypoint>,
        width: Int,
        height: Int,
        mirrored: Boolean,
        clock: String,
        round: String,
        exercise: String,
        reps: String,
        debug: Boolean = false
    ) {
        state = State(keypoints, width, height, mirrored, clock, round, exercise, reps, debug)
    }

    fun clear() {
        state = null
    }

    /** Runs on the effect's handler thread. Returns false if the frame should be dropped. */
    fun draw(frame: Frame): Boolean {
        val canvas = frame.overlayCanvas
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        val s = state ?: return true
        if (s.width <= 0 || s.height <= 0) return true

        val size = frame.size
        if (size.width <= 0 || size.height <= 0) return true

        // The keypoints are mirrored for the selfie camera; the buffer may not be.
        val bodyMirrored = s.mirrored != frame.isMirroring

        canvas.save()
        canvas.concat(transform(frame, s, mirror = bodyMirrored))
        if (s.debug) drawFrameBorder(canvas, s)
        drawSkeleton(canvas, s)
        canvas.restore()

        // Text follows the buffer, never the keypoints, so it reads forwards in the file.
        canvas.save()
        canvas.concat(transform(frame, s, mirror = false))
        drawHud(canvas, s)
        drawWatermark(canvas, s)
        canvas.restore()
        return true
    }

    /**
     * Maps the upright analysis frame onto the recorded buffer.
     *
     * An earlier version composed this out of `sensorToBufferTransform` on both streams. That
     * put the overlay in a corner at a fraction of its size: the analysis matrix is a default
     * that stays identity unless asked for, so the composition was effectively mapping
     * analysis-sized coordinates through a full sensor-to-buffer scale.
     *
     * This version needs only the two things every frame reports for itself — its size and how
     * far it has to be rotated to be displayed — plus the analysis frame's own dimensions. The
     * fit is the same FILL_CENTER the preview uses, so the recording is framed like the screen
     * and nothing is stretched.
     */
    private fun transform(frame: Frame, s: State, mirror: Boolean): Matrix {
        val affine = OverlayTransform.build(
            srcWidth = s.width,
            srcHeight = s.height,
            bufferWidth = frame.size.width,
            bufferHeight = frame.size.height,
            rotationDegrees = frame.rotationDegrees,
            mirror = mirror
        )
        return Matrix().apply { setValues(affine.values()) }
    }

    /** Outlines the mapped frame, so a misaligned overlay is obvious in the recording. */
    private fun drawFrameBorder(canvas: Canvas, s: State) {
        val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ACCENT
            style = Paint.Style.STROKE
            strokeWidth = s.height * 0.006f
        }
        canvas.drawRect(0f, 0f, s.width.toFloat(), s.height.toFloat(), edge)
    }

    private fun drawSkeleton(canvas: Canvas, s: State) {
        // Stroke widths are relative to the frame, so they survive the scale into the buffer.
        bone.strokeWidth = s.height * 0.010f
        val jointRadius = s.height * 0.008f
        for ((a, b) in KP.SKELETON) {
            val pa = s.keypoints[a]
            val pb = s.keypoints[b]
            if (pa.score < MIN_SCORE || pb.score < MIN_SCORE) continue
            canvas.drawLine(pa.x, pa.y, pb.x, pb.y, bone)
        }
        for (p in s.keypoints) {
            if (p.score < MIN_SCORE) continue
            canvas.drawCircle(p.x, p.y, jointRadius, joint)
        }
    }

    private fun drawHud(canvas: Canvas, s: State) {
        val pad = s.height * 0.018f
        val big = s.height * 0.045f
        val small = s.height * 0.025f

        text.textSize = big
        accentText.textSize = small

        // top-left: the clock
        val clockWidth = text.measureText(s.clock)
        roundedPanel(canvas, pad, pad, pad * 2 + clockWidth, pad + big * 1.5f)
        canvas.drawText(s.clock, pad * 1.5f, pad + big * 1.1f, text)

        // top-right: the round
        accentText.textAlign = Paint.Align.RIGHT
        val roundWidth = accentText.measureText(s.round)
        roundedPanel(
            canvas,
            s.width - pad * 2 - roundWidth, pad,
            s.width - pad, pad + small * 2f
        )
        canvas.drawText(s.round, s.width - pad * 1.5f, pad + small * 1.4f, accentText)
        accentText.textAlign = Paint.Align.LEFT

        // bottom-left: movement and rep count
        val label = s.exercise
        val count = s.reps
        text.textSize = big
        accentText.textSize = small
        val blockWidth = maxOf(text.measureText(count), accentText.measureText(label))
        val blockTop = s.height - pad - big * 1.6f - small * 1.4f
        roundedPanel(canvas, pad, blockTop, pad * 2 + blockWidth, s.height - pad)
        canvas.drawText(label, pad * 1.5f, blockTop + small * 1.2f, accentText)
        canvas.drawText(count, pad * 1.5f, blockTop + small * 1.4f + big * 1.1f, text)
    }

    private fun drawWatermark(canvas: Canvas, s: State) {
        val pad = s.height * 0.018f
        mark.textSize = s.height * 0.030f
        markSub.textSize = s.height * 0.016f
        canvas.drawText("CINDY", s.width - pad, s.height - pad - markSub.textSize * 1.4f, mark)
        canvas.drawText("cindy tracker", s.width - pad, s.height - pad, markSub)
    }

    private fun roundedPanel(canvas: Canvas, left: Float, top: Float, right: Float, bottom: Float) {
        val radius = (bottom - top) * 0.28f
        canvas.drawRoundRect(RectF(left, top, right, bottom), radius, radius, panel)
    }

    private companion object {
        const val MIN_SCORE = 0.30f
        val ACCENT = Color.parseColor("#00E5A0")
    }
}
