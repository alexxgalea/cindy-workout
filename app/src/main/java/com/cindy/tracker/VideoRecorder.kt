package com.cindy.tracker

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.core.CameraEffect
import androidx.camera.effects.OverlayEffect
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import android.os.Handler
import android.os.HandlerThread
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Films the workout to the device gallery, started and stopped by hand.
 *
 * Video only — no audio, which keeps the app clear of the microphone permission and stops it
 * recording its own voice counting back at you.
 */
class VideoRecorder(private val context: Context) {

    private companion object {
        const val TAG = "Cindy"
        const val FOLDER = "Movies/Cindy"
    }

    /** Bound as a camera use case; null until [buildUseCase] succeeds. */
    var useCase: VideoCapture<Recorder>? = null
        private set

    /** Draws the skeleton, score and watermark into the recorded stream. */
    val overlay = RecordingOverlay()

    private var recording: Recording? = null
    private var effect: OverlayEffect? = null
    private var effectThread: HandlerThread? = null

    val isRecording: Boolean get() = recording != null

    /** Builds the use case to hand to `bindToLifecycle`. */
    fun buildUseCase(): VideoCapture<Recorder> {
        val recorder = Recorder.Builder()
            .setQualitySelector(
                QualitySelector.from(
                    Quality.HD,
                    androidx.camera.video.FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)
                )
            )
            .build()
        return VideoCapture.withOutput(recorder).also { useCase = it }
    }

    fun forgetUseCase() {
        stop()
        useCase = null
        releaseEffect()
    }

    /**
     * Builds the effect that paints over the recorded frames.
     *
     * Targets VIDEO_CAPTURE only: the preview already has its own overlay view, and pointing the
     * effect at both would draw the skeleton twice on screen.
     */
    fun buildEffect(): CameraEffect? = try {
        releaseEffect()
        val thread = HandlerThread("cindy-overlay").also { it.start() }
        effectThread = thread
        OverlayEffect(
            CameraEffect.VIDEO_CAPTURE,
            /* queueDepth = */ 0,
            Handler(thread.looper)
        ) { t -> Log.e(TAG, "overlay effect failed", t) }
            .also { built ->
                built.setOnDrawListener { frame -> overlay.draw(frame) }
                effect = built
            }
    } catch (t: Throwable) {
        Log.w(TAG, "could not build the overlay effect", t)
        releaseEffect()
        null
    }

    private fun releaseEffect() {
        try {
            effect?.close()
        } catch (t: Throwable) {
            Log.w(TAG, "closing the effect failed", t)
        }
        effect = null
        effectThread?.quitSafely()
        effectThread = null
    }

    /**
     * Starts filming.
     *
     * @param onEvent reports the saved file's name on success, or null if it failed.
     * @return false if there is nothing bound to record with.
     */
    fun start(onEvent: (String?) -> Unit): Boolean {
        val capture = useCase ?: return false
        if (recording != null) return true

        val stamp = SimpleDateFormat("yyyy-MM-dd-HHmmss", Locale.US).format(Date())
        val name = "cindy-$stamp"
        val details = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, FOLDER)
            }
        }
        val options = MediaStoreOutputOptions
            .Builder(context.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            .setContentValues(details)
            .build()

        return try {
            recording = capture.output
                .prepareRecording(context, options)
                .start(ContextCompat.getMainExecutor(context)) { event ->
                    if (event is VideoRecordEvent.Finalize) {
                        recording = null
                        if (event.hasError()) {
                            Log.e(TAG, "recording failed: ${event.error}")
                            onEvent(null)
                        } else {
                            onEvent(name)
                        }
                    }
                }
            true
        } catch (t: Throwable) {
            Log.e(TAG, "could not start recording", t)
            recording = null
            false
        }
    }

    fun stop() {
        try {
            recording?.stop()
        } catch (t: Throwable) {
            Log.w(TAG, "stop failed", t)
        }
        recording = null
    }
}
