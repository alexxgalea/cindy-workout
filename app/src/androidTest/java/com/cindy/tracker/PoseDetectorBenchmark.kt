package com.cindy.tracker

import android.graphics.Bitmap
import android.graphics.Color
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith

/**
 * What the model actually costs on this handset, per thread count and per variant.
 *
 * ### Why this needs no video
 *
 * A fixed-input-size CNN does the same arithmetic whatever the pixels are, so inference *timing*
 * is data-independent even though *accuracy* is not. That splits the Thunder-versus-Lightning
 * question cleanly in two: the speed half can be settled here in a minute with a synthetic frame,
 * and only the accuracy half needs labelled footage.
 *
 * The synthetic frame is deliberately mid-bright and textured with no pure-black pixels, because
 * PoseDetector's low-light pass skips black pixels and measures the mean of what is left — a flat
 * dark frame would make the preprocessing look faster than it is in the app.
 *
 * ### What is being asked
 *
 * `numThreads = 4` was never measured. The test device is an SDM765G: six A55s at 1.8GHz and only
 * *two* big cores (2.2 and 2.4GHz). TFLite splits an inference across its threads and joins, so
 * the slowest thread gates the whole thing, and four threads on a chip with two fast cores may
 * well be slower than two. That is the hypothesis this exists to confirm or kill.
 *
 * Run it explicitly; it is not part of the normal suite:
 *   ./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=\
 *     com.cindy.tracker.PoseDetectorBenchmark
 */
@RunWith(AndroidJUnit4::class)
class PoseDetectorBenchmark {

    private companion object {
        const val TAG = "CindyBench"
        const val WARMUP = 8
        const val MEASURED = 24
        const val WIDTH = 480
        const val HEIGHT = 640
    }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    /** Mid-bright texture: representative for the brightness pass, irrelevant to the model's cost. */
    private fun syntheticFrame(): Bitmap {
        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(WIDTH * HEIGHT)
        for (y in 0 until HEIGHT) {
            for (x in 0 until WIDTH) {
                val r = 40 + (x * 173 + y * 37) % 180
                val g = 40 + (x * 61 + y * 151) % 180
                val b = 40 + (x * 97 + y * 89) % 180
                pixels[y * WIDTH + x] = Color.rgb(r, g, b)
            }
        }
        bitmap.setPixels(pixels, 0, WIDTH, 0, 0, WIDTH, HEIGHT)
        return bitmap
    }

    private fun median(values: LongArray): Long {
        val sorted = values.clone()
        sorted.sort()
        return sorted[sorted.size / 2]
    }

    private fun thermalNote(): String =
        try {
            val f = java.io.File("/sys/class/thermal/thermal_zone0/temp")
            if (f.canRead()) "zone0=${f.readText().trim()}" else "thermal unreadable"
        } catch (t: Throwable) {
            "thermal unreadable"
        }

    /**
     * The rotation fold, measured against the path it replaced.
     *
     * Path A is what the app used to do: allocate a second full-frame bitmap with
     * `Bitmap.createBitmap(raw, …, matrix, true)`, then hand that to the detector. Path B is what
     * it does now: give the detector the raw buffer and the map, and let it compose the rotation
     * into the crop it was already drawing.
     *
     * Both are timed end to end, because the saving is not inside the detector — it is the bitmap
     * that no longer exists. The keypoints are compared too: the fold is only worth having if the
     * geometry is unchanged, and that is a claim about this model on this device, not about the
     * matrix algebra, which is checked on the JVM in UprightTransformTest.
     */
    @Test
    fun rotationFoldVersusRotatedBitmap() {
        val raw = syntheticFrame()                    // 480x640 standing in for a sensor buffer
        val rotation = 90
        val upright = OverlayTransform.upright(raw.width, raw.height, rotation, mirror = false)
        val uw = OverlayTransform.uprightWidth(raw.width, raw.height, rotation).toInt()
        val uh = OverlayTransform.uprightHeight(raw.width, raw.height, rotation).toInt()

        val rotateMatrix = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }

        fun pathA(d: PoseDetector): Array<Keypoint> {
            val turned = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, rotateMatrix, true)
            val k = d.detect(turned)
            turned.recycle()
            return k
        }
        fun pathB(d: PoseDetector) = d.detect(raw, upright, uw, uh)

        val lines = mutableListOf<String>()
        var agreement = ""
        for (model in listOf(PoseDetector.THUNDER, PoseDetector.LIGHTNING)) {
            val label = if (model == PoseDetector.THUNDER) "thndr" else "lite"
            val times = mutableMapOf<String, Long>()
            var ka: Array<Keypoint>? = null
            var kb: Array<Keypoint>? = null
            // Interleaved A/B/A/B so thermal drift lands on both equally.
            for (name in listOf("A", "B")) {
                val d = PoseDetector(context, model)
                try {
                    repeat(WARMUP) { if (name == "A") pathA(d) else pathB(d) }
                    val t = LongArray(MEASURED)
                    for (i in 0 until MEASURED) {
                        val t0 = SystemClock.elapsedRealtimeNanos()
                        val k = if (name == "A") pathA(d) else pathB(d)
                        t[i] = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000L
                        if (i == MEASURED - 1) { if (name == "A") ka = k else kb = k }
                    }
                    times[name] = median(t)
                } finally { d.close() }
            }
            val a = times.getValue("A"); val b = times.getValue("B")
            lines += "%-6s rotated-bitmap=%3dms  folded=%3dms  saved=%3dms".format(label, a, b, a - b)

            // Largest disagreement between the two paths, in frame pixels, over seen keypoints.
            var worst = 0f
            for (i in 0 until KP.COUNT) {
                val pa = ka!![i]; val pb = kb!![i]
                if (pa.score < 0.3f && pb.score < 0.3f) continue
                worst = maxOf(worst, kotlin.math.hypot(pa.x - pb.x, pa.y - pb.y))
            }
            agreement += " $label:worst ${"%.1f".format(worst)}px"
        }
        lines.forEach { Log.i(TAG, it) }
        Log.i(TAG, "keypoint agreement:$agreement")

        val out = java.io.File(context.getExternalFilesDir(null), "rotation_fold.txt")
        out.writeText(
            "device=${android.os.Build.MODEL} thermal=${thermalNote()}\n" +
                lines.joinToString("\n") + "\nkeypoint agreement:$agreement\n"
        )
    }

    @Test
    fun modelAndThreadSweep() {
        val frame = syntheticFrame()
        Log.i(TAG, "=== BEGIN sweep · ${thermalNote()} ===")
        val results = mutableListOf<String>()

        // Forward then reversed, because a sweep that only ever counts upwards cannot tell a
        // slow thread count from a hot phone: the last configuration measured is always the one
        // that ran warmest. Running 4 threads first in the second pass puts it in the coolest
        // slot, so anything that survives both orders is a property of the thread count.
        for ((label, order) in listOf("up" to (1..4).toList(), "down" to (4 downTo 1).toList())) {
        for (model in listOf(PoseDetector.THUNDER, PoseDetector.LIGHTNING)) {
            for (threads in order) {
                val detector = PoseDetector(context, model, threads)
                try {
                    repeat(WARMUP) { detector.detect(frame) }

                    val inference = LongArray(MEASURED)
                    val wall = LongArray(MEASURED)
                    for (i in 0 until MEASURED) {
                        val t0 = SystemClock.elapsedRealtimeNanos()
                        detector.detect(frame)
                        wall[i] = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000L
                        inference[i] = detector.lastInferenceMs
                    }
                    // prep is the whole call minus the model: crop, brightness pass, input fill.
                    val line = "%-4s %-6s threads=%d  inference=%3dms  prep=%3dms  total=%3dms".format(
                        label,
                        if (model == PoseDetector.THUNDER) "thndr" else "lite",
                        threads,
                        median(inference),
                        median(wall) - median(inference),
                        median(wall)
                    )
                    Log.i(TAG, line)
                    results += line
                } finally {
                    detector.close()
                }
            }
        }
        Log.i(TAG, "--- pass '$label' done · ${thermalNote()} ---")
        }
        Log.i(TAG, "=== END sweep · ${thermalNote()} ===")
        println(results.joinToString("\n", prefix = "\n--- PoseDetector sweep ---\n"))

        // Also written to a file, because logcat is not a reliable channel here: ColorOS keeps a
        // small ring buffer and a minute of instrumentation is enough to push the results out of
        // it. A file survives, and `adb pull` does not care how long the run took.
        val out = java.io.File(context.getExternalFilesDir(null), "pose_benchmark.txt")
        out.writeText(
            buildString {
                append("device=").append(android.os.Build.MODEL)
                append(" android=").append(android.os.Build.VERSION.RELEASE)
                append(" thermal=").append(thermalNote()).append('\n')
                results.forEach { append(it).append('\n') }
            }
        )
        Log.i(TAG, "written to ${out.absolutePath}")
    }
}
