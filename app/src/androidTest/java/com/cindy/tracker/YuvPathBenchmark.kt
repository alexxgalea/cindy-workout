package com.cindy.tracker

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.hypot

/**
 * Reading the camera's planes directly, measured against converting the whole frame first.
 *
 * Path A is what CameraX was being asked to do: hand over an RGBA bitmap of every pixel, which
 * the detector then cropped and copied twice more. Path B samples the crop straight out of Y, U
 * and V.
 *
 * ### Why this one needs a real body
 *
 * The thread sweep could use synthetic texture because inference time is data-independent. This
 * cannot. The question here is not "how fast" but "does the counter still see the same person",
 * and a pose model fed noise produces unstable garbage that would make any agreement figure
 * meaningless. So it runs on a frame lifted from one of the project's own pull-up fixtures, and
 * reports the worst keypoint displacement in frame pixels along with the confidence change.
 *
 * A non-zero displacement is expected and is the point: YUV to RGB is not the identity, and how
 * far it moves a keypoint is exactly what decides whether this change is safe to ship.
 */
@RunWith(AndroidJUnit4::class)
class YuvPathBenchmark {

    private companion object {
        const val TAG = "CindyBench"
        const val WARMUP = 6
        const val MEASURED = 20
    }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    /** BT.601 full range, the inverse of what YuvCrop applies. */
    private fun toYuv(bitmap: Bitmap): YuvFrame {
        val w = bitmap.width
        val h = bitmap.height
        val px = IntArray(w * h)
        bitmap.getPixels(px, 0, w, 0, 0, w, h)
        val y = ByteArray(w * h)
        val u = ByteArray((w / 2) * (h / 2))
        val v = ByteArray((w / 2) * (h / 2))
        for (row in 0 until h) {
            for (col in 0 until w) {
                val p = px[row * w + col]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                y[row * w + col] = (0.299f * r + 0.587f * g + 0.114f * b).toInt()
                    .coerceIn(0, 255).toByte()
                if (row % 2 == 0 && col % 2 == 0) {
                    val ci = (row / 2) * (w / 2) + (col / 2)
                    u[ci] = (-0.168736f * r - 0.331264f * g + 0.5f * b + 128f).toInt()
                        .coerceIn(0, 255).toByte()
                    v[ci] = (0.5f * r - 0.418688f * g - 0.081312f * b + 128f).toInt()
                        .coerceIn(0, 255).toByte()
                }
            }
        }
        return YuvFrame().apply { set(w, h, y, w, 1, u, v, w / 2, 1) }
    }

    private fun median(v: LongArray): Long = v.clone().also { it.sort() }[v.size / 2]

    @Test
    fun yuvPathVersusRgbaBitmap() {
        val probe = File(context.getExternalFilesDir(null), "probe.png")
        assumeTrue("SKIPPED: push probe.png to ${probe.absolutePath} first", probe.exists())
        val bitmap = BitmapFactory.decodeFile(probe.absolutePath)
            .copy(Bitmap.Config.ARGB_8888, false)
        val yuv = toYuv(bitmap)
        val w = bitmap.width
        val h = bitmap.height

        val lines = mutableListOf<String>()
        for (model in listOf(PoseDetector.THUNDER, PoseDetector.LIGHTNING)) {
            val label = if (model == PoseDetector.THUNDER) "thndr" else "lite"
            val times = mutableMapOf<String, Long>()
            var ka: Array<Keypoint>? = null
            var kb: Array<Keypoint>? = null
            for (path in listOf("rgba", "yuv")) {
                val d = PoseDetector(context, model)
                try {
                    // ROI tracking locks on during warmup, so both paths measure the tracked case.
                    repeat(WARMUP) {
                        if (path == "rgba") d.detect(bitmap, Affine.IDENTITY, w, h)
                        else d.detect(yuv, Affine.IDENTITY, w, h)
                    }
                    val t = LongArray(MEASURED)
                    for (i in 0 until MEASURED) {
                        val t0 = SystemClock.elapsedRealtimeNanos()
                        val k = if (path == "rgba") d.detect(bitmap, Affine.IDENTITY, w, h)
                        else d.detect(yuv, Affine.IDENTITY, w, h)
                        t[i] = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000L
                        if (i == MEASURED - 1) { if (path == "rgba") ka = k else kb = k }
                    }
                    times[path] = median(t)
                } finally { d.close() }
            }
            var worst = 0f
            var worstName = -1
            var seen = 0
            var scoreDrift = 0f
            for (i in 0 until KP.COUNT) {
                val pa = ka!![i]; val pb = kb!![i]
                if (pa.score < 0.3f && pb.score < 0.3f) continue
                seen++
                scoreDrift = maxOf(scoreDrift, kotlin.math.abs(pa.score - pb.score))
                val dist = hypot(pa.x - pb.x, pa.y - pb.y)
                if (dist > worst) { worst = dist; worstName = i }
            }
            lines += "%-6s rgba=%3dms yuv=%3dms saved=%3dms | seen=%2d worstShift=%.2fpx (kp %d) worstScoreDelta=%.3f"
                .format(label, times.getValue("rgba"), times.getValue("yuv"),
                    times.getValue("rgba") - times.getValue("yuv"), seen, worst, worstName, scoreDrift)
        }
        lines.forEach { Log.i(TAG, it) }
        File(context.getExternalFilesDir(null), "yuv_path.txt")
            .writeText("frame=${w}x${h}\n" + lines.joinToString("\n") + "\n")
    }
}
