package com.cindy.tracker

import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraEffect
import androidx.camera.core.CameraInfo
import androidx.camera.core.Preview
import androidx.camera.effects.OverlayEffect
import java.util.concurrent.atomic.AtomicInteger

/**
 * THROWAWAY probe for #106 (skeleton sync). Lives on prototype/skeleton-sync-probe, never main.
 *
 * Modes (intent extra "probe"):
 *  - analysed: ask the picture effect for each analysed frame by that frame's capture timestamp.
 *  - sensor:   ask it for every frame by the sensor timestamp from the per-capture results.
 *  - bindtest: try the binding combinations and log which the phone accepts.
 * Everything is logged under tag CindyProbe.
 */
@OptIn(ExperimentalCamera2Interop::class)
object SyncProbe {
    const val TAG = "CindyProbe"

    @Volatile var mode: String = "none"

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    var effect: OverlayEffect? = null
        private set

    private val found = AtomicInteger()
    private val notFound = AtomicInteger()
    private val other = AtomicInteger()
    private val drawn = AtomicInteger()
    private val asked = AtomicInteger()

    val active: Boolean get() = mode == "analysed" || mode == "sensor" || mode == "bindtest"

    fun buildEffect(): CameraEffect? {
        release()
        if (!active) return null
        val t = HandlerThread("cindy-probe").also { it.start() }
        thread = t
        val h = Handler(t.looper)
        handler = h
        found.set(0); notFound.set(0); other.set(0); drawn.set(0); asked.set(0)
        return OverlayEffect(CameraEffect.PREVIEW, /* queueDepth = */ 8, h) { e ->
            Log.e(TAG, "preview effect failed", e)
        }.also { fx ->
            fx.setOnDrawListener { _ -> drawn.incrementAndGet(); true }
            effect = fx
        }
    }

    fun release() {
        try { effect?.close() } catch (_: Throwable) {}
        effect = null
        thread?.quitSafely()
        thread = null
        handler = null
    }

    /** Hooks the per-capture results onto the preview, for "sensor" mode. */
    fun instrument(builder: Preview.Builder) {
        if (mode != "sensor" && mode != "bindtest") return
        Camera2Interop.Extender(builder).setSessionCaptureCallback(
            object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    result: TotalCaptureResult
                ) {
                    val ts = result.get(CaptureResult.SENSOR_TIMESTAMP) ?: return
                    // Give the frame time to reach the effect's queue before asking for it.
                    handler?.postDelayed({ ask(ts) }, 60)
                }
            }
        )
    }

    /** An analysed frame's capture timestamp, for "analysed" mode. */
    fun onAnalysed(captureNanos: Long) {
        if (mode != "analysed") return
        ask(captureNanos)
    }

    private fun ask(ts: Long) {
        val fx = effect ?: return
        val n = asked.incrementAndGet()
        try {
            val f = fx.drawFrameAsync(ts)
            f.addListener({
                val code = try { f.get() } catch (t: Throwable) { -99 }
                when (code) {
                    OverlayEffect.RESULT_SUCCESS -> found.incrementAndGet()
                    OverlayEffect.RESULT_FRAME_NOT_FOUND -> notFound.incrementAndGet()
                    else -> other.incrementAndGet()
                }
                if (n % 50 == 0) report()
            }, Runnable::run)
        } catch (t: Throwable) {
            other.incrementAndGet()
        }
    }

    fun report() {
        Log.i(
            TAG,
            "SYNC mode=$mode asked=${asked.get()} found=${found.get()} " +
                "notFound=${notFound.get()} other=${other.get()} drawnCallbacks=${drawn.get()}"
        )
    }

    fun logClock(info: CameraInfo) {
        try {
            val c = Camera2CameraInfo.from(info)
            val src = c.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)
            val name = when (src) {
                CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME -> "REALTIME"
                CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_UNKNOWN -> "UNKNOWN(monotonic)"
                else -> "?$src"
            }
            Log.i(TAG, "CLOCK timestampSource=$name")
        } catch (t: Throwable) {
            Log.w(TAG, "CLOCK unreadable", t)
        }
    }
}
