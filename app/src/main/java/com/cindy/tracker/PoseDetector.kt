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
    val modelAsset: String = THUNDER
) {

    companion object {
        /** 256x256. Slower, and worth it at the awkward angles a floor-level phone produces. */
        const val THUNDER = "movenet_thunder.tflite"
        /** 192x192. Roughly a third of the work; the fallback if Thunder cannot keep up. */
        const val LIGHTNING = "movenet_lightning.tflite"
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

    /** True while the model is being fed a tracked crop rather than the whole frame. */
    @Volatile
    var tracking: Boolean = false
        private set

    init {
        val opts = Interpreter.Options().apply { numThreads = 4 }
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
    }

    /**
     * Runs the model on [frame] and returns 17 keypoints in **[frame] pixel coordinates**.
     * Not thread-safe: call from a single analysis thread.
     */
    fun detect(frame: Bitmap): Array<Keypoint> {
        val region = roi ?: fullFrameSquare(frame)
        tracking = roi != null

        // Map the region onto the model's square. A region reaching outside the frame simply
        // leaves black there, which is the letterbox the model expects.
        val scale = inputSize / region.width()
        canvas.drawColor(Color.BLACK)
        matrix.setScale(scale, scale)
        matrix.postTranslate(-region.left * scale, -region.top * scale)
        canvas.drawBitmap(frame, matrix, paint)

        square.getPixels(squarePixels, 0, inputSize, 0, 0, inputSize, inputSize)
        inputBuffer.rewind()
        if (inputIsFloat) {
            for (p in squarePixels) {
                inputBuffer.putFloat(((p shr 16) and 0xFF).toFloat())
                inputBuffer.putFloat(((p shr 8) and 0xFF).toFloat())
                inputBuffer.putFloat((p and 0xFF).toFloat())
            }
        } else {
            for (p in squarePixels) {
                inputBuffer.put(((p shr 16) and 0xFF).toByte())
                inputBuffer.put(((p shr 8) and 0xFF).toByte())
                inputBuffer.put((p and 0xFF).toByte())
            }
        }
        inputBuffer.rewind()

        val t0 = System.currentTimeMillis()
        interpreter.run(inputBuffer, output)
        lastInferenceMs = System.currentTimeMillis() - t0

        val raw = output[0][0]
        val side = region.width()
        val keypoints = Array(KP.COUNT) { i ->
            Keypoint(
                x = region.left + raw[i][1] * side,
                y = region.top + raw[i][0] * side,
                score = raw[i][2]
            )
        }

        updateRoi(keypoints, frame.width, frame.height)
        return keypoints
    }

    /** The whole frame expressed as a square, so a portrait image is letterboxed not cropped. */
    private fun fullFrameSquare(frame: Bitmap): RectF {
        val side = max(frame.width, frame.height).toFloat()
        return RectF(
            (frame.width - side) / 2f,
            (frame.height - side) / 2f,
            (frame.width + side) / 2f,
            (frame.height + side) / 2f
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
