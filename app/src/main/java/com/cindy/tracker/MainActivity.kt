package com.cindy.tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.net.Uri
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
import android.widget.TextView
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
        const val PREFS = "cindy"
        const val KEY_MUSIC = "music_uri"
        const val KEY_VOICE = "voice_on"
    }

    private enum class State { IDLE, SETUP, RUNNING, PAUSED, FINISHED }

    /**
     * An immutable read of the engine taken on the analysis thread.
     *
     * The engine is mutated from the camera thread and read from the main thread, so the UI is
     * driven from a snapshot rather than from live fields. It also carries the movement that was
     * just completed, which the engine has already advanced past by the time the UI sees it.
     */
    private data class Snapshot(
        val exercise: Exercise,
        val reps: Int,
        val rounds: Int,
        val repsThisRound: Int,
        val totalReps: Int,
        val hint: String,
        val event: RepEvent,
        val completed: Exercise?,
        val signal: Float,
        val phase: RepCounter.Phase,
        val range: Float,
        val calibrated: Boolean,
        val bodyVisible: Boolean
    )

    private lateinit var binding: ActivityMainBinding
    private lateinit var analysisExecutor: ExecutorService
    private lateinit var speaker: Speaker
    private lateinit var music: MusicPlayer
    private lateinit var records: RecordStore

    @Volatile private var detector: PoseDetector? = null
    private val engine = WorkoutEngine()
    private val engineLock = Any()

    @Volatile private var state = State.IDLE
    private var remainingMs = WORKOUT_MS
    private var lastTickAt = 0L
    private var lastAnnouncedSec = -1
    private var musicEnabled = true
    private var debug = false
    /** Set from the UI, acted on by the analysis thread, which owns the detector. */
    @Volatile private var pendingModel: String? = null

    @Volatile private var lensFacing = CameraSelector.LENS_FACING_BACK
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
                announceTime()
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

    private val pickMusic = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let { adoptTrack(it) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        analysisExecutor = Executors.newSingleThreadExecutor()
        records = RecordStore(this)
        music = MusicPlayer(this)
        speaker = Speaker(this).apply {
            enabled = prefs().getBoolean(KEY_VOICE, true)
            onSpeakingChanged = { speaking -> ui.post { music.duck(speaking) } }
        }

        try {
            detector = PoseDetector(this)
        } catch (t: Throwable) {
            Log.e(TAG, "MoveNet failed to load", t)
            binding.status.text = "Pose model failed to load — manual counting only"
        }

        restoreTrack()

        binding.btnStart.setOnClickListener { toggleRun() }
        binding.btnFlip.setOnClickListener { flipCamera() }
        binding.btnFlip.setOnLongClickListener {
            // Whether Thunder's accuracy is worth its latency is a question about this phone,
            // so make it answerable on this phone.
            val next = if (detector?.modelAsset == PoseDetector.THUNDER) {
                PoseDetector.LIGHTNING
            } else {
                PoseDetector.THUNDER
            }
            pendingModel = next
            toast("Switching to ${if (next == PoseDetector.THUNDER) "Thunder" else "Lightning"}")
            true
        }
        binding.btnSkip.setOnClickListener { onManualRep() }
        binding.btnSkip.setOnLongClickListener {
            if (state == State.RUNNING) apply(runEngine { engine.skipExercise() })
            true
        }
        binding.btnVoice.setOnClickListener { toggleVoice() }
        binding.btnMusic.setOnClickListener { onMusicTapped() }
        binding.btnMusic.setOnLongClickListener { pickMusic.launch(arrayOf("audio/*")); true }
        binding.btnRecords.setOnClickListener { startActivity(Intent(this, RecordsActivity::class.java)) }
        binding.status.setOnLongClickListener {
            debug = !debug
            toast(if (debug) "Debug readout on" else "Debug readout off")
            true
        }

        renderClock()
        apply(runEngine { RepEvent.NONE })
        renderChips()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) startCamera() else requestCamera.launch(Manifest.permission.CAMERA)
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    // ── camera ────────────────────────────────────────────────────────────────

    private fun startCamera() {
        binding.status.text = "Press START to set up"
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
        detector?.resetRoi()
        bindUseCases()
    }

    /** Runs on [analysisExecutor]; must never touch views directly. */
    private fun analyse(proxy: ImageProxy) {
        pendingModel?.let { asset ->
            pendingModel = null
            try {
                detector?.close()
                detector = PoseDetector(this, asset)
            } catch (t: Throwable) {
                Log.e(TAG, "could not swap model to $asset", t)
            }
        }
        val det = detector
        if (det == null || !analysing.compareAndSet(false, true)) {
            proxy.close()
            return
        }
        try {
            val frame = proxy.toUprightBitmap(mirror = lensFacing == CameraSelector.LENS_FACING_FRONT)
            val keypoints = det.detect(frame)
            val now = SystemClock.elapsedRealtime()
            val snap = if (state == State.RUNNING) {
                runEngine { engine.onFrame(keypoints, now) }
            } else {
                null
            }
            val setup = if (state == State.SETUP) {
                synchronized(engineLock) { engine.onSetupFrame(keypoints, now) }
            } else {
                null
            }
            ui.post {
                binding.overlay.setPose(keypoints, frame.width, frame.height)
                if (snap != null && state == State.RUNNING) apply(snap)
                if (setup != null && state == State.SETUP) applySetup(setup)
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

    // ── engine access ─────────────────────────────────────────────────────────

    /** Mutates the engine under lock and returns what the UI needs to render the result. */
    private fun runEngine(block: () -> RepEvent): Snapshot = synchronized(engineLock) {
        val before = engine.exercise
        val event = block()
        Snapshot(
            exercise = engine.exercise,
            reps = engine.reps,
            rounds = engine.rounds,
            repsThisRound = engine.repsThisRound,
            totalReps = engine.totalReps,
            hint = engine.hint,
            event = event,
            completed = if (event == RepEvent.EXERCISE_DONE || event == RepEvent.ROUND_DONE) before else null,
            signal = engine.signal,
            phase = engine.phase,
            range = engine.learnedRange,
            calibrated = engine.calibrated,
            bodyVisible = engine.bodyVisible
        )
    }

    /** Everything needed to judge a miscount from across the room. */
    private fun debugLine(snap: Snapshot): String {
        val det = detector
        val ms = det?.lastInferenceMs ?: 0L
        val view = if (det?.tracking == true) "roi" else "full"
        val model = det?.modelLabel ?: "none"
        val cal = if (snap.calibrated) "cal" else "warm"
        return "%s %dms · %s · sig %.0f · rng %.0f · %s · %s".format(
            Locale.US, model, ms, view, snap.signal, snap.range, cal, snap.phase
        )
    }

    private fun apply(snap: Snapshot) {
        binding.exercise.text = snap.exercise.label
        binding.reps.text = "${snap.reps} / ${snap.exercise.target}"
        binding.rounds.text = "ROUND ${snap.rounds + 1}"
        if (state == State.RUNNING) {
            binding.status.text = if (debug) debugLine(snap) else snap.hint
            // Say plainly that nothing is being counted, rather than sitting there at zero.
            binding.status.setTextColor(
                getColor(if (snap.bodyVisible) R.color.on_surface_dim else R.color.warn)
            )
        }

        when (snap.event) {
            RepEvent.NONE -> Unit
            RepEvent.REP -> {
                buzz(35)
                speaker.say("${snap.reps}")
            }
            RepEvent.EXERCISE_DONE -> {
                buzz(90)
                snap.completed?.let { speaker.say("${it.target}") }
                speaker.queue(snap.exercise.spoken)
            }
            RepEvent.ROUND_DONE -> {
                buzz(220)
                snap.completed?.let { speaker.say("${it.target}") }
                speaker.queue("Round ${snap.rounds + 1}")
                toast("Round ${snap.rounds} done")
            }
        }
    }

    // ── setup ─────────────────────────────────────────────────────────────────

    private fun enterSetup() {
        state = State.SETUP
        synchronized(engineLock) { engine.beginSetup() }
        detector?.resetRoi()
        binding.btnStart.text = "SKIP"
        binding.exercise.text = "SET UP"
        binding.reps.text = "—"
        binding.status.setTextColor(getColor(R.color.on_surface_dim))
        binding.status.text = "Get in frame"
        speaker.say("Get in frame, then do two slow pull ups")
    }

    private fun applySetup(setup: Setup) {
        when (setup.stage) {
            SetupStage.FRAMING -> {
                binding.reps.text = "—"
                binding.status.setTextColor(getColor(R.color.warn))
                binding.status.text = "Can't see your ${setup.missing.joinToString(", ")}"
            }
            SetupStage.MOVING -> {
                binding.reps.text = "${setup.reps} / 2"
                binding.status.setTextColor(getColor(R.color.on_surface_dim))
                binding.status.text = if (debug) {
                    "calibrating · rng %.0f / %.0f".format(Locale.US, setup.range, setup.needed)
                } else {
                    "Do 2 slow pull-ups to calibrate"
                }
            }
            SetupStage.POOR -> {
                binding.reps.text = "${setup.reps} / 2"
                binding.status.setTextColor(getColor(R.color.warn))
                binding.status.text = "Movement barely registers — raise the phone or step back"
            }
            SetupStage.READY -> beginWorkout(calibrated = true)
        }
    }

    // ── workout control ───────────────────────────────────────────────────────

    /** Starts the clock. [calibrated] only changes what is announced. */
    private fun beginWorkout(calibrated: Boolean) {
        synchronized(engineLock) { engine.finishSetup() }
        state = State.RUNNING
        lastTickAt = SystemClock.elapsedRealtime()
        binding.btnStart.text = "PAUSE"
        binding.status.setTextColor(getColor(R.color.on_surface_dim))
        binding.status.text = "Counting…"
        if (musicEnabled) music.play()
        speaker.say(if (calibrated) "Calibrated. Go." else "Go. Pull ups")
        apply(runEngine { RepEvent.NONE })
        ui.post(ticker)
    }

    private fun toggleRun() {
        when (state) {
            State.IDLE -> enterSetup()
            State.SETUP -> beginWorkout(calibrated = false)
            State.PAUSED -> {
                state = State.RUNNING
                lastTickAt = SystemClock.elapsedRealtime()
                binding.btnStart.text = "PAUSE"
                binding.status.text = "Counting…"
                if (musicEnabled) music.play()
                speaker.say("Resume")
                ui.post(ticker)
            }
            State.RUNNING -> {
                state = State.PAUSED
                binding.btnStart.text = "RESUME"
                binding.status.text = "Paused"
                music.pause()
                speaker.stop()
                ui.removeCallbacks(ticker)
            }
            State.FINISHED -> resetWorkout()
        }
    }

    private fun resetWorkout() {
        state = State.IDLE
        remainingMs = WORKOUT_MS
        lastAnnouncedSec = -1
        synchronized(engineLock) { engine.reset() }
        detector?.resetRoi()
        binding.btnStart.text = "START"
        binding.status.setTextColor(getColor(R.color.on_surface_dim))
        binding.status.text = "Press START to set up"
        binding.reps.setTextColor(getColor(R.color.on_surface))
        music.stop()
        renderClock()
        apply(runEngine { RepEvent.NONE })
    }

    private fun onManualRep() {
        if (state != State.RUNNING) return
        apply(runEngine { engine.manualRep() })
    }

    private fun finishWorkout() {
        state = State.FINISHED
        ui.removeCallbacks(ticker)
        buzz(600)
        music.stop()
        renderClock()

        val snap = runEngine { RepEvent.NONE }
        val attempt = Attempt(snap.rounds, snap.repsThisRound, System.currentTimeMillis())
        records.add(attempt)

        binding.btnStart.text = "RESET"
        binding.reps.setTextColor(getColor(R.color.warn))
        val beat = Records.beatsBenchmark(attempt)
        binding.status.text = buildString {
            append("TIME — ${attempt.scoreLabel()}  (${attempt.totalReps} reps)")
            if (beat) append("  ·  you beat ${Records.BENCHMARK_NAME}")
        }
        speaker.say("Time.")
        speaker.queue("${snap.rounds} rounds and ${snap.repsThisRound} reps")
        if (beat) speaker.queue("You beat ${Records.BENCHMARK_NAME}")
    }

    private fun announceTime() {
        val sec = (remainingMs / 1000L).toInt()
        if (sec == lastAnnouncedSec) return
        lastAnnouncedSec = sec
        when (sec) {
            600 -> speaker.queue("Ten minutes remaining")
            300 -> speaker.queue("Five minutes remaining")
            60 -> speaker.queue("One minute")
            10 -> speaker.queue("Ten seconds")
        }
    }

    // ── voice & music ─────────────────────────────────────────────────────────

    private fun toggleVoice() {
        speaker.enabled = !speaker.enabled
        prefs().edit().putBoolean(KEY_VOICE, speaker.enabled).apply()
        if (!speaker.enabled) speaker.stop() else speaker.say("Voice on")
        renderChips()
    }

    private fun onMusicTapped() {
        if (!music.hasTrack) {
            pickMusic.launch(arrayOf("audio/*"))
            return
        }
        musicEnabled = !musicEnabled
        if (musicEnabled && state == State.RUNNING) music.play() else music.pause()
        renderChips()
    }

    private fun adoptTrack(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (t: Throwable) {
            Log.w(TAG, "no persistable permission for $uri", t)
        }
        if (!music.load(uri)) {
            toast("Could not play that file")
            return
        }
        prefs().edit().putString(KEY_MUSIC, uri.toString()).apply()
        musicEnabled = true
        if (state == State.RUNNING) music.play()
        renderChips()
        toast("Music: ${music.trackName ?: "track loaded"}")
    }

    /** Reloads last session's track, quietly forgetting it if the permission has lapsed. */
    private fun restoreTrack() {
        val saved = prefs().getString(KEY_MUSIC, null) ?: return
        if (!music.load(Uri.parse(saved))) prefs().edit().remove(KEY_MUSIC).apply()
    }

    // ── rendering ─────────────────────────────────────────────────────────────

    private fun renderClock() {
        val total = (remainingMs + 999L) / 1000L
        binding.timer.text = String.format(Locale.US, "%02d:%02d", total / 60, total % 60)
    }

    private fun renderChips() {
        fun tint(view: TextView, on: Boolean) =
            view.setTextColor(getColor(if (on) R.color.accent else R.color.on_surface_dim))
        tint(binding.btnVoice, speaker.enabled)
        tint(binding.btnMusic, music.hasTrack && musicEnabled)
        binding.btnMusic.text = if (music.hasTrack) "MUSIC" else "MUSIC +"
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

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

    override fun onPause() {
        super.onPause()
        // Do not keep playing over whatever the athlete opens next.
        if (state == State.RUNNING) toggleRun() else music.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        ui.removeCallbacks(ticker)
        analysisExecutor.shutdown()
        detector?.close()
        speaker.shutdown()
        music.release()
    }
}
