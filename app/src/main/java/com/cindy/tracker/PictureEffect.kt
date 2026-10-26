package com.cindy.tracker

import android.content.Context
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.PorterDuff
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.camera.core.CameraEffect
import androidx.camera.effects.Frame
import androidx.camera.effects.OverlayEffect
import androidx.core.content.ContextCompat

/**
 * The picture on screen, drawn by the app so each frame can wait for its own skeleton.
 *
 * A queued [OverlayEffect] on the preview holds the camera's frames until they are asked for by
 * timestamp. [SkeletonSync] says which to ask for and with which skeleton, and this draws the
 * skeleton and the bar zone into that frame through [SkeletonPainter], on the frame's own
 * buffer. A frame that is never asked for is never shown.
 *
 * Drawing a queued frame discards every older one, which is why [SkeletonSync] releases in
 * capture order and why nothing here ever goes back for an older frame.
 *
 * Every call may come from any thread. The sync belongs to the effect's handler thread, so each
 * one is posted there.
 */
class PictureEffect(
    context: Context,
    val mode: SkeletonSync.Mode
) {
    private val thread = HandlerThread("cindy-picture").also { it.start() }
    private val handler = Handler(thread.looper)

    // Every frame waits too in every-frame mode, so the sync holds as many as the effect does.
    private val sync = SkeletonSync(mode, QUEUE_DEPTH) { System.nanoTime() }

    private val painter = SkeletonPainter(
        boneColor = ContextCompat.getColor(context, R.color.label),
        zoneOkColor = ContextCompat.getColor(context, R.color.state_ok),
        zoneAlertColor = ContextCompat.getColor(context, R.color.state_alert),
        resetLinePathEffect = DashPathEffect(floatArrayOf(18f, 14f), 0f)
    )

    /** What each released frame is to be drawn with, until the effect calls back for it. */
    private val drawing = HashMap<Long, SyncSkeleton?>()

    @Volatile
    private var closed = false

    private val tick = Runnable {
        if (closed) return@Runnable
        try {
            show(sync.due())
            scheduleTick()
        } catch (t: Throwable) {
            Log.e(TAG, "picture sync failed", t)
        }
    }

    private val overlay = OverlayEffect(
        CameraEffect.PREVIEW,
        QUEUE_DEPTH,
        handler
    ) { t -> Log.e(TAG, "picture effect failed", t) }.also { built ->
        built.setOnDrawListener { frame -> draw(frame) }
    }

    /** The effect to add to the use case group. */
    val effect: CameraEffect get() = overlay

    /** The model is about to analyse the frame stamped [captureNanos]. */
    fun frameKnown(captureNanos: Long) = post { show(sync.frameKnown(captureNanos)) }

    /** The skeleton computed from the frame stamped [captureNanos]. Never coalesced. */
    fun skeletonReady(captureNanos: Long, skeleton: SyncSkeleton) =
        post { show(sync.skeletonReady(captureNanos, skeleton)) }

    /** Lens flip, pause, ending the workout: show what waits, without skeletons, and stop. */
    fun releaseAll() = post { show(sync.releaseAll()) }

    /**
     * Leaving the screen, or a lens flip. Whatever waits is let go and nothing more is drawn.
     *
     * The teardown runs on the handler thread, behind any frame it is drawing, so the effect is
     * never closed under a draw call. Closing it from here raced with that and could throw on
     * the handler thread, which takes the whole app down.
     */
    fun close() {
        if (closed) return
        closed = true
        handler.post {
            handler.removeCallbacksAndMessages(null)
            try {
                overlay.close()
            } catch (t: Throwable) {
                Log.w(TAG, "closing the picture effect failed", t)
            }
            thread.quitSafely()
        }
    }

    /** Frames the cap released without a skeleton, and frames that never reached the screen. */
    val cappedCount: Int get() = sync.cappedCount
    val droppedCount: Int get() = sync.droppedCount

    private fun post(work: () -> Unit) {
        if (closed) return
        handler.post {
            if (closed) return@post
            // Whatever goes wrong here costs the picture a frame, never the app.
            try {
                work()
                scheduleTick()
                report()
            } catch (t: Throwable) {
                Log.e(TAG, "picture sync failed", t)
            }
        }
    }

    private fun scheduleTick() {
        handler.removeCallbacks(tick)
        val deadline = sync.nextDeadlineNanos() ?: return
        val waitMs = (deadline - System.nanoTime()) / 1_000_000L + 1L
        handler.postDelayed(tick, waitMs.coerceAtLeast(0L))
    }

    private var loggedMapping: Triple<Boolean, Boolean, Int>? = null
    private var drawn = 0
    private var drawnBare = 0
    private var shown = 0
    private var withSkeleton = 0
    private var notFound = 0
    private var lastLogMs = 0L

    /** One line every five seconds on the CindyPicture tag, until the readout shows these. */
    private fun report() {
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastLogMs < 5_000L) return
        lastLogMs = now
        Log.i(
            "CindyPicture",
            "shown=$shown withSkeleton=$withSkeleton capped=${sync.cappedCount} " +
                "dropped=${sync.droppedCount} notFound=$notFound drawn=$drawn bare=$drawnBare " +
                "mapping=$loggedMapping"
        )
    }

    private fun show(released: List<SkeletonSync.Released>) {
        for (r in released) {
            shown++
            if (r.skeleton != null) withSkeleton++
            drawing[r.captureNanos] = r.skeleton
            val result = overlay.drawFrameAsync(r.captureNanos)
            result.addListener({
                val outcome = try {
                    result.get()
                } catch (t: Throwable) {
                    null
                }
                // The effect no longer holds the frame, so it can never be shown. Count it
                // instead of leaving anything waiting on it.
                if (closed) return@addListener
                if (outcome != OverlayEffect.RESULT_SUCCESS) drawing.remove(r.captureNanos)
                if (outcome == OverlayEffect.RESULT_FRAME_NOT_FOUND) {
                    notFound++
                    sync.frameLost(r.captureNanos)
                }
            }, handler::post)
        }
    }

    /** Runs on the handler thread, once per frame asked for. */
    private fun draw(frame: Frame): Boolean {
        val skeleton = drawing.remove(frame.timestampNanos)
        drawn++
        if (skeleton == null) drawnBare++
        val canvas = frame.overlayCanvas
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        if (skeleton == null || skeleton.width <= 0 || skeleton.height <= 0) return true
        loggedMapping = Triple(skeleton.mirrored, frame.isMirroring, frame.rotationDegrees)
        canvas.save()
        // The keypoints are already in the space the picture is shown in: on the selfie lens
        // the preview buffer is mirrored for the screen, the same way the keypoints are. So
        // nothing is flipped here, unlike the film, whose buffer is not mirrored.
        canvas.concat(analysisToBuffer(frame, skeleton.width, skeleton.height, mirror = false))
        painter.paint(canvas, skeleton.keypoints, skeleton.height, skeleton.guide)
        canvas.restore()
        return true
    }

    private companion object {
        const val TAG = "Cindy"

        /**
         * Frames the effect holds. The cap is 250 ms, which is eight camera frames, and a
         * skeleton already ages 150 to 195 ms on the P40, so eight left no room. Every-frame mode
         * then paces a release over about one analysis interval, so sixteen: 533 ms.
         */
        const val QUEUE_DEPTH = 16
    }
}
