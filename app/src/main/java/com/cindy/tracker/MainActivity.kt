package com.cindy.tracker

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.util.Size
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.cindy.tracker.databinding.ActivityMainBinding
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : AppCompatActivity() {

    private companion object {
        const val TAG = "Cindy"
        const val WORKOUT_MS = 20 * 60 * 1000L
    }

    private enum class State { IDLE, RUNNING, PAUSED, FINISHED }

    private lateinit var binding: ActivityMainBinding
    private lateinit var analysisExecutor: ExecutorService

    private var detector: PoseDetector? = null
    private val engine = WorkoutEngine()

    private var state = State.IDLE
    private var remainingMs = WORKOUT_MS
    private var lastTickAt = 0L

    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var cameraProvider: ProcessCameraProvider? = null
    private val analysing = AtomicBoolean(false)

    private val ui = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            if (state != State.RUNNING) return
            val now = SystemClock.elapsedRealtime()
            remainingMs -= (now - lastTickAt)
            lastTickAt = now
            if (remainingMs <= 0L) {
                remainingMs = 0L
                finishWorkout()
            } else {
                renderClock()
                ui.postDelayed(this, 200L)
            }
        }
    }

    private val requestCamera = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startCamera()
        else binding.status.text = "Camera permission is required to count reps"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        analysisExecutor = Executors.newSingleThreadExecutor()

        try {
            detector = PoseDetector(this)
        } catch (t: Throwable) {
            Log.e(TAG, "MoveNet failed to load", t)
            binding.status.text = "Pose model failed to load — manual counting only"
        }

        binding.btnStart.setOnClickListener { toggleRun() }
        binding.btnFlip.setOnClickListener { flipCamera() }
        binding.btnSkip.setOnClickListener { onManualRep() }
        binding.btnSkip.setOnLongClickListener {
            if (state == State.RUNNING) {
                handleEvent(engine.skipExercise())
                renderScore()
                toast("Skipped to ${engine.exercise.label}")
            }
            true
        }

        renderClock()
        renderScore()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) startCamera() else requestCamera.launch(Manifest.permission.CAMERA)
    }

    // ── camera ────────────────────────────────────────────────────────────────

    private fun startCamera() {
        binding.status.text = "Press START, then get in frame"
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                cameraProvider = future.get()
                bindUseCases()
            } catch (t: Throwable) {
                Log.e(TAG, "Camera init failed", t)
                binding.status.text = "Camera unavailable: ${t.message}"
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bindUseCases() {
        val provider = cameraProvider ?: return

        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(binding.preview.surfaceProvider)
        }

        val resolution = ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(
                    Size(480, 640),
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                )
            )
            .build()

        val analysis = ImageAnalysis.Builder()
            .setResolutionSelector(resolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()
            .also { it.setAnalyzer(analysisExecutor, ::analyse) }

        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()

        provider.unbindAll()
        try {
            provider.bindToLifecycle(this, selector, preview, analysis)
        } catch (t: Throwable) {
            Log.e(TAG, "bindToLifecycle failed", t)
            binding.status.text = "Could not open camera: ${t.message}"
        }
    }

    private fun flipCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        binding.overlay.clear()
        bindUseCases()
    }

    /** Runs on [analysisExecutor]; must never touch views directly. */
    private fun analyse(proxy: ImageProxy) {
        val det = detector
        if (det == null || !analysing.compareAndSet(false, true)) {
            proxy.close()
            return
        }
        try {
            val frame = proxy.toUprightBitmap(mirror = lensFacing == CameraSelector.LENS_FACING_FRONT)
            val keypoints = det.detect(frame)
            val now = SystemClock.elapsedRealtime()
            val event = if (state == State.RUNNING) engine.onFrame(keypoints, now) else RepEvent.NONE

            ui.post {
                binding.overlay.setPose(keypoints, frame.width, frame.height)
                if (state == State.RUNNING) {
                    handleEvent(event)
                    renderScore()
                    binding.status.text = engine.hint
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "analysis failed", t)
        } finally {
            analysing.set(false)
            proxy.close()
        }
    }

    /** Rotates the analysis frame to display orientation, mirroring it for the selfie camera. */
    private fun ImageProxy.toUprightBitmap(mirror: Boolean): Bitmap {
        val raw = toBitmap()
        val rotation = imageInfo.rotationDegrees
        if (rotation == 0 && !mirror) return raw
        val m = Matrix().apply {
            postRotate(rotation.toFloat())
            // Mirror after rotation so it matches how PreviewView flips the front camera.
            if (mirror) postScale(-1f, 1f)
        }
        return Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
    }

    // ── workout control ───────────────────────────────────────────────────────

    private fun toggleRun() {
        when (state) {
            State.IDLE, State.PAUSED -> {
                state = State.RUNNING
                lastTickAt = SystemClock.elapsedRealtime()
                binding.btnStart.text = "PAUSE"
                binding.status.text = "Counting…"
                ui.post(ticker)
            }
            State.RUNNING -> {
                state = State.PAUSED
                binding.btnStart.text = "RESUME"
                binding.status.text = "Paused"
                ui.removeCallbacks(ticker)
            }
            State.FINISHED -> resetWorkout()
        }
    }

    private fun resetWorkout() {
        state = State.IDLE
        remainingMs = WORKOUT_MS
        engine.reset()
        binding.btnStart.text = "START"
        binding.status.text = "Press START, then get in frame"
        binding.reps.setTextColor(getColor(R.color.on_surface))
        renderClock()
        renderScore()
    }

    private fun onManualRep() {
        if (state != State.RUNNING) return
        handleEvent(engine.manualRep())
        renderScore()
    }

    private fun handleEvent(event: RepEvent) {
        when (event) {
            RepEvent.NONE -> Unit
            RepEvent.REP -> buzz(35)
            RepEvent.EXERCISE_DONE -> buzz(90)
            RepEvent.ROUND_DONE -> {
                buzz(220)
                toast("Round ${engine.rounds} done")
            }
        }
    }

    private fun finishWorkout() {
        state = State.FINISHED
        ui.removeCallbacks(ticker)
        buzz(600)
        renderClock()
        binding.btnStart.text = "RESET"
        binding.status.text =
            "TIME — ${engine.rounds} rounds + ${engine.repsThisRound} reps  (${engine.totalReps} total)"
        binding.reps.setTextColor(getColor(R.color.warn))
    }

    // ── rendering ─────────────────────────────────────────────────────────────

    private fun renderClock() {
        val total = (remainingMs + 999L) / 1000L
        binding.timer.text = String.format(Locale.US, "%02d:%02d", total / 60, total % 60)
    }

    private fun renderScore() {
        binding.exercise.text = engine.exercise.label
        binding.reps.text = "${engine.reps} / ${engine.exercise.target}"
        binding.rounds.text = "ROUND ${engine.rounds + 1}"
    }

    private fun toast(msg: String) =
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun buzz(ms: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    override fun onDestroy() {
        super.onDestroy()
        ui.removeCallbacks(ticker)
        analysisExecutor.shutdown()
        detector?.close()
    }
}
