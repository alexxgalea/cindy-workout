package com.cindy.tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.math.max

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
 * MoveNet SinglePose Lightning running on TFLite.
 *
 * The model wants a square image, so the frame is letterboxed rather than centre-cropped:
 * cropping reliably clips wrists overhead during pull-ups, which is exactly the signal the
 * pull-up counter depends on.
 */
class PoseDetector(context: Context, modelAsset: String = "movenet_lightning.tflite") {

    private val interpreter: Interpreter
    private val inputSize: Int
    private val inputIsFloat: Boolean
    private val inputBuffer: ByteBuffer
    private val output = Array(1) { Array(1) { Array(KP.COUNT) { FloatArray(3) } } }

    private val square: Bitmap
    private val squarePixels: IntArray
    private val canvas: Canvas
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val srcRect = Rect()
    private val dstRect = RectF()

    /** Milliseconds spent inside the last `Interpreter.run` — surfaced in the HUD. */
    @Volatile
    var lastInferenceMs: Long = 0L
        private set

    init {
        val opts = Interpreter.Options().apply { numThreads = 4 }
        interpreter = Interpreter(loadModel(context, modelAsset), opts)

        val inTensor = interpreter.getInputTensor(0)
        // MoveNet ships as [1, S, S, 3]; read S from the model rather than hard-coding 192 so
        // dropping in the Thunder (256) or a float build needs no code change.
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

    /**
     * Runs the model on [frame] and returns 17 keypoints in **[frame] pixel coordinates**.
     * Not thread-safe: call from a single analysis thread.
     */
    fun detect(frame: Bitmap): Array<Keypoint> {
        // ── letterbox into the square input ──
        val scale = inputSize.toFloat() / max(frame.width, frame.height)
        val drawW = frame.width * scale
        val drawH = frame.height * scale
        val padX = (inputSize - drawW) / 2f
        val padY = (inputSize - drawH) / 2f

        canvas.drawColor(Color.BLACK)
        srcRect.set(0, 0, frame.width, frame.height)
        dstRect.set(padX, padY, padX + drawW, padY + drawH)
        canvas.drawBitmap(frame, srcRect, dstRect, paint)

        // ── pack pixels ──
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

        // ── undo the letterbox so callers work in frame pixels ──
        val raw = output[0][0]
        return Array(KP.COUNT) { i ->
            val yn = raw[i][0] * inputSize
            val xn = raw[i][1] * inputSize
            Keypoint(
                x = (xn - padX) / scale,
                y = (yn - padY) / scale,
                score = raw[i][2]
            )
        }
    }

    fun close() = interpreter.close()
}
