package com.cindy.tracker

import androidx.camera.core.CameraEffect
import androidx.camera.effects.Frame

/**
 * The film's effect: every frame the camera captured, encoded with its own skeleton, or one
 * interpolated between its neighbours, or none when the cap fired. It is always in every-frame
 * mode, whatever the picture on screen does, because for the film the wait costs nothing and
 * the file keeps the camera's frame rate.
 *
 * The burned-in HUD is [RecordingOverlay]'s, unchanged.
 */
class FilmEffect(private val overlay: RecordingOverlay) :
    SyncedEffect(
        CameraEffect.VIDEO_CAPTURE, SkeletonSync.Mode.EVERY_FRAME, "CindyFilm", "cindy-film"
    ) {

    override fun paint(frame: Frame, skeleton: SyncSkeleton?) {
        overlay.draw(frame, skeleton)
    }
}
