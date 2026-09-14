package com.cindy.tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.math.max
import kotlin.math.min

/** A single COCO keypoint, in the coordinate space of the *source* bitmap (pixels). */
data class Keypoint(val x: Float, val y: Float, val score: Float)

/** COCO-17 keypoint indices, in the order MoveNet emits them. */
object KP {
    const val NOSE = 0
    const val LEFT_EYE = 1
    const val RIGHT_EYE = 2
    const val LEFT_EAR = 3
    const val RIGHT_EAR = 4
    const val LEFT_SHOULDER = 5
    const val RIGHT_SHOULDER = 6
    const val LEFT_ELBOW = 7
    const val RIGHT_ELBOW = 8
    const val LEFT_WRIST = 9
    const val RIGHT_WRIST = 10
    const val LEFT_HIP = 11
    const val RIGHT_HIP = 12
    const val LEFT_KNEE = 13
    const val RIGHT_KNEE = 14
    const val LEFT_ANKLE = 15
    const val RIGHT_ANKLE = 16
    const val COUNT = 17

    /** Bone list used to draw the skeleton. */
    val SKELETON = arrayOf(
        LEFT_SHOULDER to RIGHT_SHOULDER,
        LEFT_SHOULDER to LEFT_ELBOW,
        LEFT_ELBOW to LEFT_WRIST,
        RIGHT_SHOULDER to RIGHT_ELBOW,
        RIGHT_ELBOW to RIGHT_WRIST,
        LEFT_SHOULDER to LEFT_HIP,
        RIGHT_SHOULDER to RIGHT_HIP,
        LEFT_HIP to RIGHT_HIP,
        LEFT_HIP to LEFT_KNEE,
        LEFT_KNEE to LEFT_ANKLE,
        RIGHT_HIP to RIGHT_KNEE,
        RIGHT_KNEE to RIGHT_ANKLE
    )
}

/**
 * MoveNet SinglePose running on TFLite, with region-of-interest tracking.
 *
 * ### Why the crop matters
 *
 * MoveNet resizes whatever it is given down to a small square. A phone standing on the floor
 * puts the athlete in a slice of a tall frame, so feeding it whole spends most of those pixels
 * on ceiling and carpet and leaves the body a few dozen pixels tall — which is where the
 * keypoints get mushy and the rep counter starts guessing.
 *
 * So each frame is cropped to a square around where the body was last seen, and the model sees
 * a body that fills the input. The crop follows the athlete, grows a margin around them, and
 * falls back to the whole frame whenever tracking is lost.
 */
class PoseDetector(
    context: Context,
    val modelAsset: String = THUNDER,
    /**
     * Interpreter threads. TFLite splits each inference across them and joins, so the slowest
     * thread gates the result — which makes this a question about the *layout* of the CPU, not
     * the number of cores on it. Benchmarked per device rather than assumed; see
     * PoseDetectorBenchmark.
     */
    private val threads: Int = DEFAULT_THREADS
) {

    companion object {
        /** 256x256. Slower, and worth it at the awkward angles a floor-level phone produces. */
        const val THUNDER = "movenet_thunder.tflite"
        /** 192x192. Roughly a third of the work; the fallback if Thunder cannot keep up. */
        const val LIGHTNING = "movenet_lightning.tflite"
        /** Unmeasured until 2026-09-14; see PoseDetectorBenchmark for what the device says. */
        const val DEFAULT_THREADS = 4
    }

    /** Short name for the debug readout. */
    val modelLabel: String get() = if (modelAsset == THUNDER) "thndr" else "lite"


    private object Tune {
        const val MIN_SCORE = 0.30f
        /** Confident keypoints needed to trust the crop for the next frame. */
        const val MIN_TRACKED = 5
        /** Consecutive poor frames before giving up and re-scanning the whole image. */
        const val MAX_MISSES = 5
        /** How much room to leave around the body, as a multiple of its bounding box. */
        const val MARGIN = 1.45f
        /** Crop is never allowed below this share of the frame, to avoid chasing noise. */
        const val MIN_CROP_FRACTION = 0.25f
        /** Per-frame follow rate of the crop, damping jitter. */
        const val FOLLOW = 0.35f
        /**
         * Mean luma a dark crop is lifted towards before inference. Below the ~116 a well-exposed
         * fixture measures, so ordinary footage passes through untouched and cannot move.
         */
        const val TARGET_LUMA = 110f
        /** Ceiling on that lift. Past this the frame is noise, and gain only amplifies it. */
        const val MAX_SOFT_GAIN = 16f
    }

    private val interpreter: Interpreter
    private val inputSize: Int
    private val inputIsFloat: Boolean
    private val inputBuffer: ByteBuffer
    private val output = Array(1) { Array(1) { Array(KP.COUNT) { FloatArray(3) } } }

    private val square: Bitmap
    private val squarePixels: IntArray
    private val canvas: Canvas
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val matrix = Matrix()

    /** Square crop in source-bitmap pixels; null means "look at the whole frame". */
    private var roi: RectF? = null
    private var misses = 0

    @Volatile
    var lastInferenceMs: Long = 0L
        private set

    /**
     * What the crop, the brightness pass and the input fill cost, separately from the model.
     *
     * Split out because the two want opposite fixes and nothing had ever told them apart: if the
     * model dominates, the answer is a smaller model or a delegate; if this does, the answer is
     * in the bitmap plumbing, and swapping the model would be wasted accuracy.
     */
    @Volatile
    var lastPrepMs: Long = 0L
        private set

    /** True while the model is being fed a tracked crop rather than the whole frame. */
    @Volatile
    var tracking: Boolean = false
        private set

    /**
     * What the last crop had to be brightened by. 1.0 means the picture needed no help.
     *
     * Read by TrackingHealthMonitor, which is the only evidence the app has about whether a frame
     * it could not read was dark or merely empty.
     */
    @Volatile
    var softGain: Float = 1f
        private set

    init {
        val opts = Interpreter.Options().apply { numThreads = threads }
        interpreter = Interpreter(loadModel(context, modelAsset), opts)

        val inTensor = interpreter.getInputTensor(0)
        // Read the square size from the model so Lightning (192) and Thunder (256) both drop in.
        inputSize = inTensor.shape()[1]
        inputIsFloat = inTensor.dataType() == DataType.FLOAT32

        val bytesPerChannel = if (inputIsFloat) 4 else 1
        inputBuffer = ByteBuffer
            .allocateDirect(inputSize * inputSize * 3 * bytesPerChannel)
            .order(ByteOrder.nativeOrder())

        square = Bitmap.createBitmap(inputSize, inputSize, Bitmap.Config.ARGB_8888)
        squarePixels = IntArray(inputSize * inputSize)
        canvas = Canvas(square)
    }

    private fun loadModel(context: Context, asset: String): ByteBuffer {
        context.assets.openFd(asset).use { fd ->
            FileInputStream(fd.fileDescriptor).use { stream ->
                return stream.channel.map(
                    FileChannel.MapMode.READ_ONLY,
                    fd.startOffset,
                    fd.declaredLength
                )
            }
        }
    }

    /** Forgets the tracked crop — call when the camera changes or a workout restarts. */
    fun resetRoi() {
        roi = null
        misses = 0
        tracking = false
        softGain = 1f
    }

    /**
     * Runs the model on [frame] and returns 17 keypoints in **upright-frame pixel coordinates**.
     *
     * [frame] is the camera's raw buffer, still in sensor orientation. [upright] maps it into the
     * frame the rest of the app reasons in, and [uprightWidth]/[uprightHeight] are that frame's
     * size — see [OverlayTransform.upright] for why the rotation arrives as a matrix rather than
     * as an already-rotated bitmap.
     *
     * Not thread-safe: call from a single analysis thread.
     */
    fun detect(
        frame: Bitmap,
        upright: Affine = Affine.IDENTITY,
        uprightWidth: Int = frame.width,
        uprightHeight: Int = frame.height
    ): Array<Keypoint> {
        val tPrep = System.nanoTime()
        val region = beginFrame(uprightWidth, uprightHeight)

        // Raw buffer -> upright frame -> the model's square, composed into one draw. A region
        // reaching outside the frame simply leaves black there, which is the letterbox the model
        // expects.
        canvas.drawColor(Color.BLACK)
        matrix.setValues(sourceToModel(upright, region).values())
        canvas.drawBitmap(frame, matrix, paint)

        square.getPixels(squarePixels, 0, inputSize, 0, 0, inputSize, inputSize)
        return infer(region, uprightWidth, uprightHeight, tPrep)
    }

    /**
     * The same, reading the camera's YUV planes directly instead of a converted bitmap.
     *
     * This is the path the app uses. The bitmap overload is kept because it is the only way to
     * measure this one against what it replaced — see PoseDetectorBenchmark.
     */
    fun detect(
        frame: YuvFrame,
        upright: Affine,
        uprightWidth: Int,
        uprightHeight: Int
    ): Array<Keypoint> {
        val tPrep = System.nanoTime()
        val region = beginFrame(uprightWidth, uprightHeight)
        val inverse = sourceToModel(upright, region).invert()
        if (inverse == null) {
            squarePixels.fill(0)
        } else {
            YuvCrop.sample(frame, inverse, squarePixels, inputSize)
        }
        return infer(region, uprightWidth, uprightHeight, tPrep)
    }

    /** Picks this frame's crop and records whether it is a tracked one. */
    private fun beginFrame(uprightWidth: Int, uprightHeight: Int): RectF {
        val region = roi ?: fullFrameSquare(uprightWidth, uprightHeight)
        tracking = roi != null
        return region
    }

    /** Raw camera coordinates to the model's input square, through the upright frame. */
    private fun sourceToModel(upright: Affine, region: RectF): Affine {
        val scale = inputSize / region.width()
        return upright
            .then(Affine.scale(scale, scale))
            .then(Affine.translate(-region.left * scale, -region.top * scale))
    }

    /** Everything from the filled input square onward, shared by both ways of filling it. */
    private fun infer(
        region: RectF,
        uprightWidth: Int,
        uprightHeight: Int,
        tPrep: Long
    ): Array<Keypoint> {
        val gain = normalisingGain(squarePixels)
        softGain = gain
        inputBuffer.rewind()
        if (inputIsFloat) {
            for (p in squarePixels) {
                inputBuffer.putFloat(lift((p shr 16) and 0xFF, gain))
                inputBuffer.putFloat(lift((p shr 8) and 0xFF, gain))
                inputBuffer.putFloat(lift(p and 0xFF, gain))
            }
        } else {
            for (p in squarePixels) {
                inputBuffer.put(lift((p shr 16) and 0xFF, gain).toInt().toByte())
                inputBuffer.put(lift((p shr 8) and 0xFF, gain).toInt().toByte())
                inputBuffer.put(lift(p and 0xFF, gain).toInt().toByte())
            }
        }
        inputBuffer.rewind()

        // nanoTime, not currentTimeMillis: the latter has millisecond granularity against a
        // figure that may well be single digits, and it can step sideways when the clock is
        // corrected. This number is now being used to make decisions, so it has to be a duration.
        val t0 = System.nanoTime()
        lastPrepMs = (t0 - tPrep) / 1_000_000L
        interpreter.run(inputBuffer, output)
        lastInferenceMs = (System.nanoTime() - t0) / 1_000_000L

        val raw = output[0][0]
        val side = region.width()
        val keypoints = Array(KP.COUNT) { i ->
            Keypoint(
                x = region.left + raw[i][1] * side,
                y = region.top + raw[i][0] * side,
                score = raw[i][2]
            )
        }

        updateRoi(keypoints, uprightWidth, uprightHeight)
        return keypoints
    }

    /**
     * How much the crop must be brightened to reach [Tune.TARGET_LUMA], clamped so it can only
     * ever lift a dark frame and never touch a well-exposed one.
     *
     * MoveNet does not normalise its own input, so a picture the camera left underexposed fails
     * for a reason that is representational rather than informational: the detail is still there,
     * the numbers are just small. Measured against a clip whose ground truth is five reps and
     * which had been darkened until it scored zero, this brings back all five, and extends the
     * usable range at least 3.3x further into the dark. It also turned out to fix a documented
     * miscount on an ordinary fixture — a rear-view clip that scored 9 of 10 because a dead hang
     * projected 149 degrees against a 150 degree threshold now scores 10 — which says that clip
     * was underexposed all along and nobody had noticed.
     *
     * Measured on the *crop*, not the frame, which is the point. Auto-exposure meters the whole
     * scene, so an athlete against a window or a bright ceiling is left dark inside a frame whose
     * average looks perfectly healthy. The crop is already centred on the body.
     *
     * What it cannot do is rescue a noisy frame. Once the camera has raised its own gain to the
     * limit the information is gone, and multiplying amplifies the noise along with the signal —
     * measured at no improvement at all. That is what makes the returned value worth reporting:
     * a large gain that does not restore legibility means the light is genuinely gone.
     */
    private fun normalisingGain(pixels: IntArray): Float {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var lit = 0
        for (p in pixels) {
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            // Pure black is either the letterbox around a crop that reached outside the frame or
            // a pixel carrying nothing anyway. Excluding it stops the letterbox dragging the mean
            // down and over-brightening the part that matters, and biases what is left towards
            // under-correcting, which is the safe direction.
            if (r or g or b == 0) continue
            red += r
            green += g
            blue += b
            lit++
        }
        if (lit == 0) return 1f
        // Channel means first, then the weighted sum, which is the order the Python port takes
        // them in; summing per pixel instead would round differently and the two would drift.
        val mean = (0.299 * red + 0.587 * green + 0.114 * blue).toFloat() / lit
        return (Tune.TARGET_LUMA / max(mean, 1f)).coerceIn(1f, Tune.MAX_SOFT_GAIN)
    }

    /** Applies [gain] to one 0-255 channel, clamped so a bright pixel cannot wrap to black. */
    private fun lift(channel: Int, gain: Float): Float =
        if (gain <= 1f) channel.toFloat() else min(channel * gain, 255f)

    /** The whole frame expressed as a square, so a portrait image is letterboxed not cropped. */
    private fun fullFrameSquare(width: Int, height: Int): RectF {
        val side = max(width, height).toFloat()
        return RectF(
            (width - side) / 2f,
            (height - side) / 2f,
            (width + side) / 2f,
            (height + side) / 2f
        )
    }

    /** Re-aims the crop at wherever the body just was, or drops it if the body was lost. */
    private fun updateRoi(k: Array<Keypoint>, frameW: Int, frameH: Int) {
        val seen = k.filter { it.score >= Tune.MIN_SCORE }
        if (seen.size < Tune.MIN_TRACKED) {
            if (++misses >= Tune.MAX_MISSES) resetRoi()
            return
        }
        misses = 0

        var left = Float.MAX_VALUE
        var top = Float.MAX_VALUE
        var right = -Float.MAX_VALUE
        var bottom = -Float.MAX_VALUE
        for (p in seen) {
            left = min(left, p.x); right = max(right, p.x)
            top = min(top, p.y); bottom = max(bottom, p.y)
        }

        val longest = max(max(frameW, frameH).toFloat(), 1f)
        val side = (max(right - left, bottom - top) * Tune.MARGIN)
            .coerceIn(longest * Tune.MIN_CROP_FRACTION, longest)
        val cx = (left + right) / 2f
        val cy = (top + bottom) / 2f

        val target = RectF(cx - side / 2f, cy - side / 2f, cx + side / 2f, cy + side / 2f)
        val current = roi
        roi = if (current == null) target else RectF(
            current.left + (target.left - current.left) * Tune.FOLLOW,
            current.top + (target.top - current.top) * Tune.FOLLOW,
            current.right + (target.right - current.right) * Tune.FOLLOW,
            current.bottom + (target.bottom - current.bottom) * Tune.FOLLOW
        )
    }

    fun close() = interpreter.close()
}
