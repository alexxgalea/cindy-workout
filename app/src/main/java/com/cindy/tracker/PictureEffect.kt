package com.cindy.tracker

import android.content.Context
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.PorterDuff
import androidx.camera.core.CameraEffect
import androidx.camera.effects.Frame
import androidx.core.content.ContextCompat

/**
 * The picture on screen, drawn by the app so each frame can wait for its own skeleton.
 *
 * The skeleton and the bar zone are drawn into the frame through [SkeletonPainter], on the
 * frame's own buffer.
 */
class PictureEffect(
    context: Context,
    mode: SkeletonSync.Mode
) : SyncedEffect(CameraEffect.PREVIEW, mode, "CindyPicture", "cindy-picture") {

    private val painter = SkeletonPainter(
        boneColor = ContextCompat.getColor(context, R.color.label),
        zoneOkColor = ContextCompat.getColor(context, R.color.state_ok),
        zoneAlertColor = ContextCompat.getColor(context, R.color.state_alert),
        resetLinePathEffect = DashPathEffect(floatArrayOf(18f, 14f), 0f)
    )

    private var loggedMapping: Triple<Boolean, Boolean, Int>? = null

    override fun mappingNote(): String = "mapping=$loggedMapping"

    override fun paint(frame: Frame, skeleton: SyncSkeleton?) {
        val canvas = frame.overlayCanvas
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        if (skeleton == null || skeleton.width <= 0 || skeleton.height <= 0) return
        loggedMapping = Triple(skeleton.mirrored, frame.isMirroring, frame.rotationDegrees)
        canvas.save()
        // The keypoints are already in the space the picture is shown in: on the selfie lens
        // the preview buffer is mirrored for the screen, the same way the keypoints are. So
        // nothing is flipped here, unlike the film, whose buffer is not mirrored.
        canvas.concat(analysisToBuffer(frame, skeleton.width, skeleton.height, mirror = false))
        painter.paint(canvas, skeleton.keypoints, skeleton.height, skeleton.guide)
        canvas.restore()
    }
}
