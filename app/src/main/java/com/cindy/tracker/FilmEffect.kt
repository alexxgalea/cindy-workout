package com.cindy.tracker

import androidx.camera.core.CameraEffect
import androidx.camera.effects.Frame

/**
 * The film's effect: every frame the camera captured, encoded with its own skeleton, or one
 * interpolated between its neighbours, or none when the cap fired. The file keeps the camera's
 * frame rate, and the wait costs nothing because nobody watches the film as it is made.
 *
 * The burned-in HUD is [RecordingOverlay]'s, unchanged.
 */
class FilmEffect(private val overlay: RecordingOverlay) :
    SyncedEffect(CameraEffect.VIDEO_CAPTURE, "CindyFilm", "cindy-film") {

    override fun paint(frame: Frame, skeleton: SyncSkeleton?) {
        overlay.draw(frame, skeleton)
    }
}
