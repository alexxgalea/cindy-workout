package com.cindy.tracker

import android.Manifest
import android.app.AlertDialog
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
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.updateLayoutParams
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
        const val KEY_PROFILE = "movement_profile"
    }

    private enum class State { IDLE, SETUP, RUNNING, PAUSED, FINISHED }

    /**
     * A HUD field that is only written when it actually changes.
     *
     * The analysis thread posts a frame of UI work at camera rate, and almost none of those
     * frames change any of this text; setting it anyway costs a measure and a layout each time.
     * Holding the current value here also lets the burned-in recording overlay be fed from
     * plain strings instead of reading four TextViews back on the hot path.
     */
    private class HudText(private val view: TextView) {
        private var shown: String? = null
        private var spoken: String? = null
        private var colour: Int? = null

        var text: String
            get() = shown.orEmpty()
            set(value) {
                if (shown == value) return
                shown = value
                view.text = value
            }

        /** What a screen reader should say, for fields whose glyphs do not read aloud well. */
        fun spoken(value: String) {
            if (spoken == value) return
            spoken = value
            view.contentDescription = value
        }

        fun colour(argb: Int) {
            if (colour == argb) return
            colour = argb
            view.setTextColor(argb)
        }
    }

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
        val bodyVisible: Boolean,
        val blocked: Boolean,
        val awaitingStart: Boolean,
        val manualReps: Int
    )

    private lateinit var binding: ActivityMainBinding
    private lateinit var clock: HudText
    private lateinit var round: HudText
    private lateinit var exercise: HudText
    private lateinit var reps: HudText
    private lateinit var status: HudText
    private var dim = 0
    private var warn = 0
    private var accent = 0
    private var onSurface = 0
    private lateinit var analysisExecutor: ExecutorService
    private lateinit var speaker: Speaker
    private lateinit var music: MusicPlayer
    private lateinit var video: VideoRecorder
    private lateinit var records: RecordStore

    @Volatile private var detector: PoseDetector? = null
    /**
     * Rebuilt rather than mutated when the movements change.
     *
     * [WorkoutEngine.profile] is immutable for the life of an engine on purpose: a rep's meaning
     * must not change halfway through the score it contributes to.
     */
    @Volatile private var engine = WorkoutEngine()
    private val engineLock = Any()

    @Volatile private var state = State.IDLE
    private var remainingMs = WORKOUT_MS
    private var lastTickAt = 0L
    private var lastAnnouncedSec = -1
    /** Wall time of each completed round, and when the current one started. */
    private val roundSplits = mutableListOf<Long>()
    /** Clock time at which the current round began, so a pause cannot inflate its split. */
    private var roundStartedAtElapsed = 0L
    private var elapsedMs = 0L
    private var pausedMs = 0L
    private var pauseStartedAt = 0L
    private var musicEnabled = true
    private var debug = false
    /** Decides what the voice says about the athlete's position. Tested on its own.  */
    private val coach = Coach()
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
            val step = now - lastTickAt
            remainingMs -= step
            elapsedMs += step
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
        else status.text = "Camera permission is required to count reps"
    }

    private val pickMusic = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let { adoptTrack(it) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The camera fills the window; the HUD is moved off the system bars in code, because
        // padding the root would letterbox the preview along with the overlay.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        clock = HudText(binding.timer)
        round = HudText(binding.rounds)
        exercise = HudText(binding.exercise)
        reps = HudText(binding.reps)
        status = HudText(binding.status)
        dim = getColor(R.color.on_surface_dim)
        warn = getColor(R.color.warn)
        accent = getColor(R.color.accent)
        onSurface = getColor(R.color.on_surface)

        analysisExecutor = Executors.newSingleThreadExecutor()
        records = RecordStore(this)
        music = MusicPlayer(this)
        video = VideoRecorder(this)
        speaker = Speaker(this).apply {
            enabled = prefs().getBoolean(KEY_VOICE, true)
            onSpeakingChanged = { speaking -> ui.post { music.duck(speaking) } }
        }

        try {
            detector = PoseDetector(this)
        } catch (t: Throwable) {
            Log.e(TAG, "MoveNet failed to load", t)
            status.text = "Pose model failed to load — manual counting only"
        }

        restoreTrack()

        binding.btnStart.setOnClickListener { toggleRun() }
        binding.btnFlip.setOnClickListener { onLeftButton() }
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
        binding.btnUndo.setOnClickListener { onUndoRep() }
        binding.btnSkip.setOnLongClickListener {
            if (state == State.RUNNING) apply(runEngine { engine.skipExercise() })
            true
        }
        binding.btnVoice.setOnClickListener { toggleVoice() }
        binding.btnMusic.setOnClickListener { onMusicTapped() }
        binding.btnMusic.setOnLongClickListener { pickMusic.launch(arrayOf("audio/*")); true }
        binding.btnRecords.setOnClickListener { startActivity(Intent(this, RecordsActivity::class.java)) }
        binding.btnHelp.setOnClickListener { startActivity(Intent(this, HelpActivity::class.java)) }
        binding.btnMoves.setOnClickListener { chooseMovements() }
        binding.btnRec.setOnClickListener { toggleRecording() }
        binding.status.setOnLongClickListener {
            debug = !debug
            toast(if (debug) "Debug readout on" else "Debug readout off")
            true
        }

        keepHudClearOfSystemBars()
        describeControls()
        renderClock()
        synchronized(engineLock) { engine = WorkoutEngine(profile = savedProfile()) }
        apply(runEngine { RepEvent.NONE })
        renderChips()
        renderControls()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) startCamera() else requestCamera.launch(Manifest.permission.CAMERA)
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    // ── window and accessibility ──────────────────────────────────────────────

    /**
     * Re-margins the overlaid HUD by whatever the system bars and the cutout are covering.
     *
     * Only the edge each view is actually anchored to is adjusted: adding the top inset to the
     * status line, which hangs off the chips above it, would just push it down the screen.
     */
    private fun keepHudClearOfSystemBars() {
        val hud = listOf(
            binding.timer, binding.rounds, binding.chips,
            binding.status, binding.repBlock, binding.controls
        )
        val base = hud.associateWith { view ->
            val lp = view.layoutParams as ViewGroup.MarginLayoutParams
            intArrayOf(lp.marginStart, lp.topMargin, lp.marginEnd, lp.bottomMargin)
        }

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { root, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val rtl = root.layoutDirection == View.LAYOUT_DIRECTION_RTL
            val start = if (rtl) bars.right else bars.left
            val end = if (rtl) bars.left else bars.right

            fun View.push(startBy: Int = 0, topBy: Int = 0, endBy: Int = 0, bottomBy: Int = 0) {
                val b = base.getValue(this)
                updateLayoutParams<ViewGroup.MarginLayoutParams> {
                    marginStart = b[0] + startBy
                    topMargin = b[1] + topBy
                    marginEnd = b[2] + endBy
                    bottomMargin = b[3] + bottomBy
                }
            }

            binding.timer.push(startBy = start, topBy = bars.top)
            binding.rounds.push(topBy = bars.top, endBy = end)
            binding.chips.push(endBy = end)
            binding.status.push(startBy = start, endBy = end)
            binding.repBlock.push(startBy = start, endBy = end)
            binding.controls.push(startBy = start, endBy = end, bottomBy = bars.bottom)
            insets
        }
    }

    /**
     * Names the controls for TalkBack, and says out loud what a long press does.
     *
     * Every control on this screen is a styled TextView, which draws correctly and is silent to
     * a screen reader: no role, no name, and no clue that four of them do a second thing when
     * held. The labels that depend on state are refreshed by [renderChips] and [renderControls].
     */
    private fun describeControls() {
        binding.btnUndo.describe("Take back a rep")
        binding.btnSkip.describe("Add a rep", longPress = "Skip to the next movement")
        binding.btnRecords.describe("Your records")
        binding.btnHelp.describe("What Cindy is, and how this app scores it")
        binding.status.describe(longPress = "Show the debug readout")
        // The rest change job with the workout: renderControls and renderChips name those, and
        // only the long presses, which never change, are declared here.
        binding.btnStart.describe()
        binding.btnFlip.describe(longPress = "Switch pose model")
        binding.btnMusic.describe(longPress = "Choose a track")
        binding.btnVoice.describe()
        binding.btnRec.describe()
    }

    /**
     * Gives a TextView a button's semantics. A null [label] keeps the view's own text as its
     * name, which is what a live status line wants.
     */
    private fun TextView.describe(label: String? = null, longPress: String? = null) {
        label?.let { contentDescription = it }
        ViewCompat.setAccessibilityDelegate(this, object : AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfoCompat
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                if (host.isClickable) info.className = Button::class.java.name
                longPress?.let {
                    info.addAction(
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat(
                            AccessibilityNodeInfoCompat.ACTION_LONG_CLICK, it
                        )
                    )
                }
            }
        })
    }

    // ── camera ────────────────────────────────────────────────────────────────

    private fun startCamera() {
        status.text = "Press START to set up"
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                cameraProvider = future.get()
                bindUseCases()
            } catch (t: Throwable) {
                Log.e(TAG, "Camera init failed", t)
                status.text = "Camera unavailable: ${t.message}"
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
        // Preview + analysis + recording is more than some cameras will bind at once, and the
        // overlay effect is another surface on top of that. Rep counting is the point of the
        // app, so the recording features are what get dropped, in order.
        val bound = bindWithOverlay(provider, selector, preview, analysis) ||
            bindPlainRecording(provider, selector, preview, analysis) ||
            bindCountingOnly(provider, selector, preview, analysis)
        if (!bound) status.text = "Could not open the camera"
        renderChips()
    }

    private fun bindWithOverlay(
        provider: ProcessCameraProvider,
        selector: CameraSelector,
        preview: Preview,
        analysis: ImageAnalysis
    ): Boolean = try {
        val effect = video.buildEffect()
        val group = UseCaseGroup.Builder()
            .addUseCase(preview)
            .addUseCase(analysis)
            .addUseCase(video.buildUseCase())
            .apply { effect?.let { addEffect(it) } }
            .build()
        provider.bindToLifecycle(this, selector, group)
        true
    } catch (t: Throwable) {
        Log.w(TAG, "could not bind the overlay effect, recording without it", t)
        false
    }

    private fun bindPlainRecording(
        provider: ProcessCameraProvider,
        selector: CameraSelector,
        preview: Preview,
        analysis: ImageAnalysis
    ): Boolean = try {
        provider.unbindAll()
        provider.bindToLifecycle(this, selector, preview, analysis, video.buildUseCase())
        true
    } catch (t: Throwable) {
        Log.w(TAG, "could not bind the recorder, continuing without it", t)
        false
    }

    private fun bindCountingOnly(
        provider: ProcessCameraProvider,
        selector: CameraSelector,
        preview: Preview,
        analysis: ImageAnalysis
    ): Boolean = try {
        provider.unbindAll()
        video.forgetUseCase()
        provider.bindToLifecycle(this, selector, preview, analysis)
        true
    } catch (t: Throwable) {
        Log.e(TAG, "bindToLifecycle failed", t)
        false
    }

    private fun flipCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        binding.overlay.clear()
        detector?.resetRoi()
        synchronized(engineLock) { engine.recalibrate() }
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
            val mirrored = lensFacing == CameraSelector.LENS_FACING_FRONT
            val frame = proxy.toUprightBitmap(mirror = mirrored)
            val keypoints = det.detect(frame)
            val now = SystemClock.elapsedRealtime()
            val snap = if (state == State.RUNNING) {
                runEngine { engine.onFrame(keypoints, now, det.tracking) }
            } else {
                null
            }
            val setup = if (state == State.SETUP) {
                synchronized(engineLock) { engine.onSetupFrame(keypoints, now, det.tracking) }
            } else {
                null
            }
            // The gate is pull-up geometry; the other two movements have no bar to draw.
            val guide = synchronized(engineLock) {
                engine.barGuide.takeIf { engine.exercise == Exercise.PULLUP }
            }
            ui.post {
                binding.overlay.setPose(keypoints, frame.width, frame.height, guide)
                if (snap != null && state == State.RUNNING) apply(snap)
                if (setup != null && state == State.SETUP) applySetup(setup)
                // Feed the burned-in overlay the same numbers the screen is showing.
                video.overlay.update(
                    keypoints = keypoints,
                    width = frame.width,
                    height = frame.height,
                    mirrored = mirrored,
                    clock = clock.text,
                    round = round.text,
                    exercise = exercise.text,
                    reps = reps.text,
                    debug = debug
                )
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
            bodyVisible = engine.bodyVisible,
            blocked = engine.blocked,
            awaitingStart = engine.awaitingStart,
            manualReps = engine.manualReps
        )
    }

    /** Everything needed to judge a miscount from across the room. */
    private fun debugLine(snap: Snapshot): String {
        val det = detector
        val ms = det?.lastInferenceMs ?: 0L
        val view = if (det?.tracking == true) "roi" else "full"
        val model = det?.modelLabel ?: "none"
        val cal = if (snap.calibrated) "cal" else "warm"
        // "start" means the movement has not been taken up yet, so nothing can score.
        val phase = if (snap.awaitingStart) "start" else snap.phase.toString()
        return "%s %dms · %s · sig %.0f · rng %.0f · %s · %s".format(
            Locale.US, model, ms, view, snap.signal, snap.range, cal, phase
        )
    }

    private fun apply(snap: Snapshot) {
        exercise.text = snap.exercise.label
        reps.text = "${snap.reps} / ${snap.exercise.target}"
        reps.spoken("${snap.reps} of ${snap.exercise.target} ${snap.exercise.label}")
        round.text = "ROUND ${snap.rounds + 1}"
        round.spoken("Round ${snap.rounds + 1}")
        if (state == State.RUNNING) {
            status.text = when {
                debug -> debugLine(snap)
                !snap.calibrated -> "Recalibrating…"
                else -> snap.hint
            }
            // Say plainly whether a rep would count right now, rather than only complaining.
            status.colour(
                when {
                    !snap.bodyVisible -> warn
                    snap.blocked -> dim
                    else -> accent
                }
            )
            speakAboutPosition(snap)
        }

        when (snap.event) {
            RepEvent.NONE -> Unit
            RepEvent.REP -> {
                buzz(35)
                speaker.say("${snap.reps}")
            }
            RepEvent.UNDO -> {
                buzz(20)
                speaker.say("${snap.reps}")
            }
            RepEvent.EXERCISE_DONE -> {
                buzz(90)
                snap.completed?.let { speaker.say("${it.target}") }
                speaker.queue(snap.exercise.spoken)
            }
            RepEvent.ROUND_DONE -> {
                buzz(220)
                val split = elapsedMs - roundStartedAtElapsed
                roundSplits += split
                roundStartedAtElapsed = elapsedMs
                snap.completed?.let { speaker.say("${it.target}") }
                speaker.queue("Round ${snap.rounds} in ${spokenDuration(split)}")
                toast("Round ${snap.rounds} · ${formatDuration(split)}")
            }
        }
    }

    /**
     * Speaks about the athlete's position, in both directions.
     *
     * Mid-set nobody is looking at the phone. A rep that will not count is otherwise lost in
     * silence until the summary screen — and, just as bad, an athlete who has got themselves
     * into a good position has no way to know the app agrees.
     */
    private fun speakAboutPosition(snap: Snapshot) {
        val say = coach.onFrame(
            exercise = snap.exercise,
            blocked = snap.blocked,
            hint = snap.hint,
            now = SystemClock.elapsedRealtime()
        )
        // Queued, so it never cuts off a rep count mid-number.
        say?.let { speaker.queue(it) }
    }

    // ── setup ─────────────────────────────────────────────────────────────────

    private fun enterSetup() {
        state = State.SETUP
        renderControls()
        synchronized(engineLock) { engine.beginSetup() }
        detector?.resetRoi()
        binding.btnStart.text = "SKIP"
        exercise.text = "SET UP"
        reps.text = "—"
        reps.spoken("Setting up")
        status.colour(dim)
        status.text = "Get in frame"
        speaker.say("Get in frame, then do two slow pull ups")
    }

    private fun applySetup(setup: Setup) {
        when (setup.stage) {
            SetupStage.FRAMING -> {
                reps.text = "—"
                reps.spoken("Setting up")
                status.colour(warn)
                status.text = "Can't see your ${setup.missing.joinToString(", ")}"
            }
            SetupStage.MOVING -> {
                reps.text = "${setup.reps} / 2"
                reps.spoken("${setup.reps} of 2 calibration reps")
                status.colour(dim)
                status.text = if (debug) {
                    "calibrating · rng %.0f / %.0f".format(Locale.US, setup.range, setup.needed)
                } else {
                    "Do 2 slow pull-ups to calibrate"
                }
            }
            SetupStage.POOR -> {
                reps.text = "${setup.reps} / 2"
                reps.spoken("${setup.reps} of 2 calibration reps")
                status.colour(warn)
                status.text = "Movement barely registers — raise the phone or step back"
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
        roundStartedAtElapsed = 0L
        roundSplits.clear()
        elapsedMs = 0L
        pausedMs = 0L
        binding.btnStart.text = "PAUSE"
        status.colour(dim)
        status.text = "Counting…"
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
                val now = SystemClock.elapsedRealtime()
                if (pauseStartedAt != 0L) {
                    pausedMs += now - pauseStartedAt
                    pauseStartedAt = 0L
                }
                lastTickAt = now
                binding.btnStart.text = "PAUSE"
                // The phone or the athlete may have moved while the clock was stopped, so the
                // band learned before the pause no longer describes what the camera is seeing.
                synchronized(engineLock) { engine.recalibrate() }
                detector?.resetRoi()
                status.text = "Recalibrating…"
                if (musicEnabled) music.play()
                speaker.say("Resume")
                ui.post(ticker)
            }
            State.RUNNING -> {
                state = State.PAUSED
                coach.interrupted()
                pauseStartedAt = SystemClock.elapsedRealtime()
                binding.btnStart.text = "RESUME"
                status.text = "Paused"
                music.pause()
                speaker.stop()
                ui.removeCallbacks(ticker)
            }
            State.FINISHED -> resetWorkout()
        }
        renderControls()
    }

    /**
     * The left button is FLIP outside a workout and STOP inside one. Flipping the camera
     * mid-Cindy is not a thing anyone does; ending early is.
     */
    private fun renderControls() {
        val inWorkout = state == State.RUNNING || state == State.PAUSED
        binding.btnFlip.text = if (inWorkout) "STOP" else "FLIP"
        binding.btnFlip.setTextColor(getColor(if (inWorkout) R.color.warn else R.color.on_surface))
        binding.btnFlip.contentDescription =
            if (inWorkout) "End the workout" else "Switch camera"
        binding.btnStart.contentDescription = when (state) {
            State.IDLE -> "Start the workout"
            State.SETUP -> "Skip the setup check"
            State.RUNNING -> "Pause"
            State.PAUSED -> "Resume"
            State.FINISHED -> "Start again"
        }
    }

    private fun onLeftButton() {
        if (state == State.RUNNING || state == State.PAUSED) confirmStop() else flipCamera()
    }

    private fun confirmStop() {
        val wasRunning = state == State.RUNNING
        if (wasRunning) toggleRun() // park the clock while the dialog is up
        AlertDialog.Builder(this)
            .setTitle("End the workout?")
            .setMessage("Your score so far will be saved.")
            .setNegativeButton("Keep going") { _, _ -> if (wasRunning) toggleRun() }
            .setPositiveButton("End") { _, _ -> finishWorkout(stoppedEarly = true) }
            .show()
    }

    private fun resetWorkout() {
        state = State.IDLE
        remainingMs = WORKOUT_MS
        lastAnnouncedSec = -1
        roundSplits.clear()
        elapsedMs = 0L
        pausedMs = 0L
        pauseStartedAt = 0L
        synchronized(engineLock) { engine.reset() }
        coach.reset()
        detector?.resetRoi()
        binding.btnStart.text = "START"
        status.colour(dim)
        status.text = "Press START to set up"
        reps.colour(onSurface)
        music.stop()
        renderClock()
        apply(runEngine { RepEvent.NONE })
    }

    private fun onManualRep() {
        if (state != State.RUNNING) return
        apply(runEngine { engine.manualRep() })
    }

    /** Takes back a rep the counter should not have scored. */
    private fun onUndoRep() {
        if (state != State.RUNNING) return
        val before = synchronized(engineLock) { engine.rounds }
        val snap = runEngine { engine.undoRep() }
        // Stepping back over a round boundary un-books that round's split too.
        if (snap.rounds < before && roundSplits.isNotEmpty()) {
            roundStartedAtElapsed = elapsedMs - roundSplits.removeAt(roundSplits.size - 1)
        }
        apply(snap)
    }

    private fun finishWorkout(stoppedEarly: Boolean = false) {
        state = State.FINISHED
        ui.removeCallbacks(ticker)
        buzz(600)
        music.stop()
        renderClock()
        renderControls()

        // A stop pressed from the pause dialog still owes its hidden time to the tally.
        if (pauseStartedAt != 0L) {
            pausedMs += SystemClock.elapsedRealtime() - pauseStartedAt
            pauseStartedAt = 0L
        }
        video.stop()

        val snap = runEngine { RepEvent.NONE }
        val attempt = Attempt(
            rounds = snap.rounds,
            reps = snap.repsThisRound,
            atMillis = System.currentTimeMillis(),
            durationMs = elapsedMs,
            pausedMs = pausedMs,
            roundSplitsMs = roundSplits.toList(),
            profile = engine.profile,
            manualReps = snap.manualReps
        )
        records.add(attempt)

        binding.btnStart.text = "RESET"
        renderControls()
        reps.colour(warn)
        val beat = Records.beatsBenchmark(attempt)
        status.colour(dim)
        status.text = "${attempt.scoreLabel()} · ${attempt.caption}"

        speaker.say(if (stoppedEarly) "Stopped." else "Time.")
        speaker.queue("${snap.rounds} rounds and ${snap.repsThisRound} reps")
        attempt.avgRoundMs?.let { speaker.queue("Averaging ${spokenDuration(it)} a round") }
        if (beat) speaker.queue("You beat ${Records.BENCHMARK_NAME}")

        startActivity(ResultsActivity.intent(this, attempt, stoppedEarly))
    }

    /** "one minute twenty" — TTS makes a mess of "1:20". */
    private fun spokenDuration(ms: Long): String {
        val total = ms / 1000L
        val m = total / 60
        val sec = total % 60
        return when {
            m == 0L -> "$sec seconds"
            sec == 0L -> "$m minute${if (m == 1L) "" else "s"}"
            else -> "$m minute${if (m == 1L) "" else "s"} $sec"
        }
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
        clock.text = String.format(Locale.US, "%02d:%02d", total / 60, total % 60)
        clock.spoken("${spokenDuration(remainingMs)} remaining")
    }

    private fun renderChips() {
        fun tint(view: TextView, on: Boolean) =
            view.setTextColor(getColor(if (on) R.color.accent else R.color.on_surface_dim))
        tint(binding.btnVoice, speaker.enabled)
        tint(binding.btnMusic, music.hasTrack && musicEnabled)
        binding.btnMusic.text = if (music.hasTrack) "MUSIC" else "MUSIC +"
        binding.btnRec.text = if (video.isRecording) "● REC" else "REC"
        binding.btnRec.setTextColor(
            getColor(if (video.isRecording) R.color.warn else R.color.on_surface_dim)
        )
        // These states live in the text colour alone, which a screen reader cannot see.
        binding.btnVoice.contentDescription =
            if (speaker.enabled) "Voice counting, on" else "Voice counting, off"
        binding.btnMusic.contentDescription = when {
            !music.hasTrack -> "Music, no track chosen"
            musicEnabled -> "Music, on"
            else -> "Music, off"
        }
        binding.btnRec.contentDescription =
            if (video.isRecording) "Stop recording" else "Record this workout"
    }

    private fun toggleRecording() {
        if (video.isRecording) {
            video.stop()
            renderChips()
            return
        }
        if (video.useCase == null) {
            toast("Recording is not available on this camera")
            return
        }
        val started = video.start { name ->
            renderChips()
            toast(if (name != null) "Saved $name to Movies/Cindy" else "Recording failed")
        }
        if (!started) toast("Could not start recording")
        renderChips()
    }

    private fun savedProfile(): CindyProfile = Variations.decode(prefs().getString(KEY_PROFILE, null))

    /**
     * "Make Cindy yours": one choice per movement, taken before the clock starts.
     *
     * Neutral names only. No "easy", "beginner", "scaled" or "cheat" — a band-assisted pull-up
     * is a different prescription, not a lesser athlete, and the app has no business
     * editorialising about which one someone ought to be doing. What it does say plainly is
     * which choices it can score with the camera and which it will ask to be tapped in, because
     * that is a fact about the app rather than a judgement about the person.
     *
     * Locked while a workout is live: the movements have to mean one thing for the whole score.
     */
    private fun chooseMovements() {
        if (state != State.IDLE && state != State.FINISHED) {
            toast("Reset first to change movements")
            return
        }
        val current = savedProfile()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(4), dp(20), dp(4))
        }
        container.addView(note("Anything other than the standard three is saved as an Adaptive " +
            "Cindy and ranked against your own sessions at the same movements."))
        val pull = variantGroup(container, "PULL", PullVariant.entries, current.pull,
            { it.label }, { it.tracking })
        val push = variantGroup(container, "PUSH", PushVariant.entries, current.push,
            { it.label }, { it.tracking })
        val squat = variantGroup(container, "SQUAT", SquatVariant.entries, current.squat,
            { it.label }, { it.tracking })

        AlertDialog.Builder(this)
            .setTitle("Make Cindy yours")
            .setView(ScrollView(this).apply { addView(container) })
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save") { _, _ ->
                applyProfile(
                    CindyProfile(
                        pull = PullVariant.entries[pull.checkedRadioButtonId],
                        push = PushVariant.entries[push.checkedRadioButtonId],
                        squat = SquatVariant.entries[squat.checkedRadioButtonId]
                    )
                )
            }
            .show()
    }

    private fun note(text: String) = TextView(this).apply {
        this.text = text
        setTextColor(getColor(R.color.on_surface_dim))
        textSize = 12f
        setPadding(0, dp(8), 0, dp(4))
    }

    /** One movement's options, as radio buttons whose ids are their ordinal. */
    private fun <T> variantGroup(
        parent: LinearLayout,
        title: String,
        options: List<T>,
        selected: T,
        label: (T) -> String,
        tracking: (T) -> Tracking
    ): RadioGroup {
        parent.addView(TextView(this).apply {
            text = title
            setTextColor(getColor(R.color.on_surface_dim))
            textSize = 11f
            setPadding(0, dp(14), 0, dp(2))
        })
        val group = RadioGroup(this)
        options.forEachIndexed { i, option ->
            group.addView(RadioButton(this).apply {
                id = i
                // Said on the option itself, so the choice and its consequence arrive together.
                text = if (tracking(option) == Tracking.MANUAL) {
                    "${label(option)}  ·  you tap +1"
                } else {
                    label(option)
                }
                textSize = 15f
                minHeight = dp(48)
            })
        }
        group.check(options.indexOf(selected))
        parent.addView(group)
        return group
    }

    private fun applyProfile(chosen: CindyProfile) {
        prefs().edit().putString(KEY_PROFILE, Variations.encode(chosen)).apply()
        synchronized(engineLock) { engine = WorkoutEngine(profile = chosen) }
        apply(runEngine { RepEvent.NONE })
        renderChips()
        renderControls()
        toast(chosen.label())
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

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
        if (state == State.RUNNING && !isChangingConfigurations) toggleRun() else music.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        ui.removeCallbacks(ticker)
        analysisExecutor.shutdown()
        detector?.close()
        speaker.shutdown()
        music.release()
        video.stop()
    }
}
