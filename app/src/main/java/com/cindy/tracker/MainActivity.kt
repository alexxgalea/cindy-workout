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
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.widget.ImageView
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
import androidx.annotation.DrawableRes
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.updateLayoutParams
import androidx.camera.view.PreviewView
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
        const val KEY_PLACEMENT_SEEN = "placement_guide_dismissed"

        /** What an unavailable control fades to: plainly off, still plainly there. */
        const val DIMMED = 0.3f
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
    private lateinit var repsTarget: HudText
    private lateinit var status: HudText
    private lateinit var coachCue: HudText
    private var ok = 0
    private var alert = 0
    private var neutral = 0
    private var label = 0

    /** The colour currently painted on the status dot, so it is only rebuilt when it changes. */
    private var statusDotColour = 0

    /**
     * When the current blocked state began, or 0 while nothing is blocked.
     *
     * The demonstrator waits this out rather than appearing the instant a gate shuts: between
     * reps of a set the gate closes and reopens constantly, and a figure that flashes up each
     * time would be worse than no figure at all.
     */
    private var blockedSince = 0L
    private var coachShowing = false

    /** How long a movement must stay un-startable before the demonstrator is worth showing. */
    private val COACH_AFTER_MS = 1_200L

    /**
     * The round and rep lines as single strings, for [RecordingOverlay].
     *
     * The HUD splits both — ROUND is a static label beside its number, and the target drops a
     * weight and a shade behind the live count — but a video burned with "4" and "3" where it
     * used to read "ROUND 4" and "3 / 5" would be strictly worse than before. The recorder is
     * fed these rather than reading the views back.
     */
    private var recordedRound = "ROUND 1"
    private var recordedReps = "0 / 5"
    private lateinit var analysisExecutor: ExecutorService
    private lateinit var speaker: Speaker
    private lateinit var music: MusicPlayer
    private lateinit var video: VideoRecorder
    private lateinit var records: RecordStore
    private lateinit var profile: Profile

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
        // Before super, so the launch window is in place for the whole of the cold start rather
        // than after it. It paints the same black this activity opens onto, so the handover to
        // LaunchView is invisible.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        // The camera fills the window; the HUD is moved off the system bars in code, because
        // padding the root would letterbox the preview along with the overlay.
        // The screen must not sleep mid-workout. This has to be the window flag set in code:
        // android:keepScreenOn is a *View* attribute, and the copy of it that used to sit on
        // <activity> in the manifest was silently ignored, so a device with a short display
        // timeout blanked the screen with the athlete across the room mid-set.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        hideSystemBars()

        clock = HudText(binding.timer)
        round = HudText(binding.rounds)
        exercise = HudText(binding.exercise)
        reps = HudText(binding.reps)
        repsTarget = HudText(binding.repsTarget)
        status = HudText(binding.status)
        coachCue = HudText(binding.coachCue)
        ok = getColor(R.color.state_ok)
        alert = getColor(R.color.state_alert)
        neutral = getColor(R.color.label_tertiary)
        label = getColor(R.color.label)
        binding.coachDot.background = dotDrawable(R.color.state_alert)
        // The one filled control on the screen is white, so its mark has to be painted black.
        binding.btnStart.imageTintList = ColorStateList.valueOf(getColor(R.color.on_primary))
        primary(R.drawable.ic_play)

        // The launch screen goes when the preview delivers a frame, which is the moment the app
        // is actually ready. The timeout covers the cases where that never happens — a refused
        // camera permission, or a device that fails to open one at all.
        binding.preview.previewStreamState.observe(this) { streaming ->
            if (streaming == PreviewView.StreamState.STREAMING) binding.launch.dismiss {}
        }
        binding.root.postDelayed({ binding.launch.dismiss {} }, 2_500L)

        analysisExecutor = Executors.newSingleThreadExecutor()
        records = RecordStore(this)
        profile = Profile(this)
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
        binding.btnEnd.setOnClickListener { confirmStop() }
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
        binding.btnAddRep.setOnClickListener { onManualRep() }
        binding.btnUndo.setOnClickListener { onUndoRep() }
        binding.btnSkipExercise.setOnClickListener { onSkip() }
        binding.btnVoice.setOnClickListener { toggleVoice() }
        binding.btnMusic.setOnClickListener { onMusicTapped() }
        binding.btnMusic.setOnLongClickListener { pickMusic.launch(arrayOf("audio/*")); true }
        binding.btnRec.setOnClickListener { toggleRecording() }
        binding.btnMenu.setOnClickListener {
            startActivity(MenuActivity.intent(this, workoutLive = inWorkout()))
        }
        binding.statusRow.setOnLongClickListener {
            debug = !debug
            toast(if (debug) "Debug readout on" else "Debug readout off")
            true
        }

        keepHudClearOfSystemBars()
        describeControls()
        renderClock()
        synchronized(engineLock) { engine = WorkoutEngine(profile = profile.movements) }
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
     * Puts the status and navigation bars away for the workout, the way a camera app does.
     *
     * The strip they occupy is a HUD row's worth of the picture, and the only clock that matters
     * mid-Cindy is the one this screen prints itself. They stay reachable: a swipe brings them
     * back over the top, transiently, without moving the layout underneath.
     */
    private fun hideSystemBars() {
        WindowInsetsControllerCompat(window, binding.root).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    /** A dialog, a permission prompt or a task switch brings them back; put them away again. */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    /**
     * Keeps the HUD clear of whatever the display cutout is covering.
     *
     * The system bars are hidden on this screen, so usually there is nothing to clear — but a
     * punch-hole or a notch still reports an inset, and the top band's first row sits exactly
     * where one lives. The bands take it as *padding*, not margin: their backgrounds have to go
     * on reaching the edges of the glass, and a margin would leave a bright strip of preview
     * above the band.
     */
    private fun keepHudClearOfSystemBars() {
        val bands = listOf(binding.bandTop, binding.bandBottom)
        val base = bands.associateWith { view ->
            intArrayOf(view.paddingLeft, view.paddingTop, view.paddingRight, view.paddingBottom)
        }
        val coachBase =
            (binding.coachCard.layoutParams as ViewGroup.MarginLayoutParams).marginStart

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { root, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val rtl = root.layoutDirection == View.LAYOUT_DIRECTION_RTL

            base.getValue(binding.bandTop).let { b ->
                binding.bandTop.setPadding(
                    b[0] + bars.left, b[1] + bars.top, b[2] + bars.right, b[3]
                )
            }
            base.getValue(binding.bandBottom).let { b ->
                binding.bandBottom.setPadding(
                    b[0] + bars.left, b[1], b[2] + bars.right, b[3] + bars.bottom
                )
            }
            binding.coachCard.updateLayoutParams<ViewGroup.MarginLayoutParams> {
                marginStart = coachBase + if (rtl) bars.right else bars.left
            }
            insets
        }
    }

    /**
     * Names the controls for TalkBack, and says out loud what a long press does.
     *
     * Every control on this screen is a styled TextView or a bare ImageView, which draws
     * correctly and is silent to a screen reader: no role, no name, and no clue that four of them
     * do a second thing when held. Since the chips became icons this matters more, not less —
     * there is no longer any text for TalkBack to fall back on.
     *
     * The labels that depend on state are refreshed by [renderChips] and [renderControls].
     */
    private fun describeControls() {
        binding.btnUndo.describeAsButton("Take back a rep")
        binding.btnAddRep.describeAsButton("Add a rep")
        binding.btnMenu.describeAsButton("Menu: records, movements, body weight and help")
        binding.statusRow.describeAsButton(longPress = "Show the debug readout")
        // The rest change job with the workout: renderControls and renderChips name those, and
        // only the long presses, which never change, are declared here.
        binding.btnStart.describeAsButton()
        binding.btnEnd.describeAsButton("End the workout")
        binding.btnFlip.describeAsButton("Switch camera", longPress = "Switch pose model")
        binding.btnMusic.describeAsButton(longPress = "Choose a track")
        binding.btnVoice.describeAsButton()
        binding.btnRec.describeAsButton()
    }

    // ── camera ────────────────────────────────────────────────────────────────

    private fun startCamera() {
        status.text = "Tap to set up"
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
                    round = recordedRound,
                    exercise = exercise.text,
                    reps = recordedReps,
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
        reps.text = "${snap.reps}"
        repsTarget.text = "/${snap.exercise.target}"
        reps.spoken("${snap.reps} of ${snap.exercise.target} ${snap.exercise.label}")
        round.text = "${snap.rounds + 1}"
        round.spoken("Round ${snap.rounds + 1}")
        recordedRound = "ROUND ${snap.rounds + 1}"
        recordedReps = "${snap.reps} / ${snap.exercise.target}"
        // Readable from the bar, when the digits are not.
        binding.repProgress.progress =
            snap.reps * 100 / snap.exercise.target.coerceAtLeast(1)
        if (state == State.RUNNING) {
            status.text = when {
                debug -> debugLine(snap)
                !snap.calibrated -> "Recalibrating…"
                else -> snap.hint
            }
            // Say plainly whether a rep would count right now, rather than only complaining.
            // The dot carries this, not the text: a sentence that changes colour as you read it
            // is harder to read, and white on glass is the most legible thing on this screen.
            statusDot(
                when {
                    !snap.bodyVisible -> alert
                    snap.blocked -> neutral
                    else -> ok
                }
            )
            speakAboutPosition(snap)
        }
        updateCoach(snap)

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
        primary(R.drawable.ic_play)
        exercise.text = "SET UP"
        reps.text = "—"
        repsTarget.text = ""
        reps.spoken("Setting up")
        statusDot(neutral)
        status.text = "Get in frame"
        speaker.say("Get in frame, then do two slow pull ups")
    }

    private fun applySetup(setup: Setup) {
        when (setup.stage) {
            SetupStage.FRAMING -> {
                reps.text = "—"
                repsTarget.text = ""
                reps.spoken("Setting up")
                statusDot(alert)
                status.text = "Can't see your ${setup.missing.joinToString(", ")}"
            }
            SetupStage.MOVING -> {
                reps.text = "${setup.reps}"
                repsTarget.text = "/2"
                reps.spoken("${setup.reps} of 2 calibration reps")
                statusDot(neutral)
                status.text = if (debug) {
                    "calibrating · rng %.0f / %.0f".format(Locale.US, setup.range, setup.needed)
                } else {
                    "Do 2 slow pull-ups to calibrate"
                }
            }
            SetupStage.POOR -> {
                reps.text = "${setup.reps}"
                repsTarget.text = "/2"
                reps.spoken("${setup.reps} of 2 calibration reps")
                statusDot(alert)
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
        primary(R.drawable.ic_pause)
        // The check hands over to the workout without going through [toggleRun], so this is the
        // only place the row learns there is a workout now: without it END never appears and the
        // rep editors stay dimmed for the whole session.
        renderControls()
        statusDot(neutral)
        status.text = "Counting…"
        if (musicEnabled) music.play()
        speaker.say(if (calibrated) "Calibrated. Go." else "Go. Pull ups")
        apply(runEngine { RepEvent.NONE })
        ui.post(ticker)
    }

    private fun toggleRun() {
        when (state) {
            State.IDLE -> showPlacementGuide { enterSetup() }
            // Unreachable: the shutter is disabled for the duration of the check, and SKIP is
            // the way out of it. Named rather than left to `else` so the state machine stays
            // readable from this one when-block.
            State.SETUP -> Unit
            State.PAUSED -> {
                state = State.RUNNING
                val now = SystemClock.elapsedRealtime()
                if (pauseStartedAt != 0L) {
                    pausedMs += now - pauseStartedAt
                    pauseStartedAt = 0L
                }
                lastTickAt = now
                primary(R.drawable.ic_pause)
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
                primary(R.drawable.ic_play)
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
     * Sets the shutter's mark. The word that used to sit beside it is gone: the states it takes
     * are the ones a player already draws, and carrying the longest of five labels is what made
     * the control wide. What the mark cannot say on its own is said twice over instead — by the
     * status line above it, and by the spoken description [renderControls] keeps in step.
     */
    private fun primary(@DrawableRes icon: Int) {
        binding.btnStart.setImageResource(icon)
    }

    /**
     * The controls of the action row, and what each is for at this moment.
     *
     * The left slot is FLIP before the clock starts and END once it is running. Only one of the
     * two is ever present: they share a position in the frame, and showing both crowded the band
     * for no gain, since flipping the camera is not something anyone does mid-Cindy while
     * getting out of a workout is.
     *
     * The shutter is the run control and nothing else. It goes inert during the setup check,
     * because there is no workout yet to run or to pause — SKIP is the way out of the check.
     *
     * The rest follow one rule: a control keeps its place and dims when it has nothing to act
     * on. Hiding them instead was tried and was worse — a band that empties out does not read as
     * tidy, it reads as a band that has lost its buttons, and you cannot learn where a control
     * lives if it is only there half the time. The left slot is not an exception to that: it
     * never empties, it changes hands.
     */
    private fun renderControls() {
        val live = inWorkout()

        binding.btnFlip.visibility = if (live) View.GONE else View.VISIBLE
        binding.btnFlip.setImageResource(R.drawable.ic_flip)
        binding.btnFlip.imageTintList = ColorStateList.valueOf(label)
        binding.btnFlip.contentDescription = "Switch camera"

        binding.btnEnd.visibility = if (live) View.VISIBLE else View.GONE
        binding.btnEnd.imageTintList = ColorStateList.valueOf(alert)

        // The editors act on a count, and the count only moves while the clock is running —
        // onManualRep and onUndoRep both refuse outside RUNNING — so a paused workout dims them
        // too, rather than offering a lit button that quietly does nothing.
        val canEdit = state == State.RUNNING
        for (editor in listOf(binding.btnUndo, binding.btnAddRep)) {
            editor.isEnabled = canEdit
            editor.alpha = if (canEdit) 1f else DIMMED
        }

        // Inert during the check, and dimmed so that it reads as unavailable rather than broken.
        val canRun = state != State.SETUP
        binding.btnStart.isEnabled = canRun
        binding.btnStart.alpha = if (canRun) 1f else DIMMED
        binding.btnStart.contentDescription = when (state) {
            State.IDLE -> "Start the workout"
            State.SETUP -> "Start — available once the setup check finishes"
            State.RUNNING -> "Pause"
            State.PAUSED -> "Resume"
            State.FINISHED -> "Start again"
        }

        // There is a movement to leave during the check and during the workout, and none before
        // the clock starts or after it stops.
        val canSkip = state == State.SETUP || live
        binding.btnSkipExercise.isEnabled = canSkip
        binding.btnSkipExercise.alpha = if (canSkip) 1f else DIMMED
        binding.btnSkipExercise.contentDescription = when (state) {
            State.SETUP -> "Skip the setup check"
            else -> "Skip to the next movement"
        }
    }

    /**
     * SKIP means the same thing everywhere — leave this movement — but leaving it during the
     * check means starting Cindy with no calibration at all, which is worth a question first.
     * Mid-workout it is not: a skipped movement is a scoring decision the athlete has made, and
     * asking twenty times a session would be the wrong trade.
     */
    private fun onSkip() {
        when (state) {
            State.SETUP -> CindySheet(
                this,
                title = "Skip the setup check?",
                subtitle = "Cindy will start counting straight away, without calibrating to " +
                    "your bar. Reps may be missed or counted twice."
            ).actions(
                primary = "SKIP",
                onPrimary = { beginWorkout(calibrated = false) },
                secondary = "KEEP CHECKING",
                onSecondary = {}
            ).show()
            State.RUNNING, State.PAUSED -> apply(runEngine { engine.skipExercise() })
            State.IDLE, State.FINISHED -> Unit
        }
    }

    /** A workout is live once the clock has started, whether or not it is ticking right now. */
    private fun inWorkout(): Boolean = state == State.RUNNING || state == State.PAUSED

    private fun confirmStop() {
        val wasRunning = state == State.RUNNING
        if (wasRunning) toggleRun() // park the clock while the dialog is up
        CindySheet(
            this,
            title = "End the workout?",
            subtitle = "Your score so far will be saved."
        ).actions(
            primary = "END",
            onPrimary = { finishWorkout(stoppedEarly = true) },
            secondary = "KEEP GOING",
            onSecondary = { if (wasRunning) toggleRun() }
        ).show()
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
        primary(R.drawable.ic_play)
        statusDot(neutral)
        status.text = "Tap to set up"
        reps.colour(label)
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
        // A recording that has not begun has nothing left to film.
        binding.countdown.cancel()
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

        primary(R.drawable.ic_again)
        renderControls()
        // Kept as it was: the finished count is painted in the alert colour so a glance at a
        // phone across the room says the clock has stopped rather than that it is still running.
        reps.colour(alert)
        val beat = Records.beatsBenchmark(attempt)
        statusDot(neutral)
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
        fun paint(view: ImageView, colour: Int, lit: Boolean) {
            view.imageTintList = ColorStateList.valueOf(colour)
            view.setBackgroundResource(if (lit) R.drawable.icon_pill_active else 0)
        }
        paint(binding.btnVoice, if (speaker.enabled) label else neutral, speaker.enabled)

        val musicOn = music.hasTrack && musicEnabled
        // Three states, not two: no track at all is dimmer again than a track that is paused.
        paint(
            binding.btnMusic,
            when {
                musicOn -> label
                music.hasTrack -> neutral
                else -> getColor(R.color.label_quaternary)
            },
            musicOn
        )
        // Lit red while filming, red but unlit while the countdown runs — the count itself is
        // on the picture, so the icon only has to say which of the three states REC is in.
        val counting = binding.countdown.isRunning
        paint(
            binding.btnRec,
            if (video.isRecording || counting) alert else neutral,
            video.isRecording
        )
        paint(binding.btnMenu, getColor(R.color.label_secondary), false)

        // The chips carry no text at all now, so a screen reader has nothing but these.
        binding.btnVoice.contentDescription =
            if (speaker.enabled) "Voice counting, on" else "Voice counting, off"
        binding.btnMusic.contentDescription = when {
            !music.hasTrack -> "Music, no track chosen"
            musicEnabled -> "Music, on"
            else -> "Music, off"
        }
        binding.btnRec.contentDescription = when {
            counting -> "Recording is about to start, tap to cancel"
            video.isRecording -> "Stop recording"
            else -> "Record this workout"
        }
    }

    /** Paints the status dot, and only when the colour actually changes. */
    private fun statusDot(argb: Int) {
        if (statusDotColour == argb) return
        statusDotColour = argb
        binding.statusDot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(argb)
        }
    }

    /**
     * Shows or hides the start-position demonstrator.
     *
     * The trigger is a state the engine already computes: [WorkoutEngine.blocked] means this
     * frame was refused for something the athlete could fix by moving, and `bodyVisible`
     * separates that from not being in shot at all. In frame, but not in position.
     *
     * It waits [COACH_AFTER_MS] out first. Between reps of a set the gate opens and shuts
     * constantly, and a figure that appeared on every one of those would be noise; a real failure
     * to get set lasts. It leaves the instant the gate opens, with no dwell at all, because by
     * then the athlete is already moving and the figure is in the way.
     */
    private fun updateCoach(snap: Snapshot) {
        val eligible = state == State.RUNNING && snap.blocked && snap.bodyVisible && !debug
        val now = SystemClock.elapsedRealtime()
        if (!eligible) blockedSince = 0L else if (blockedSince == 0L) blockedSince = now

        val show = eligible && now - blockedSince >= COACH_AFTER_MS
        if (show) {
            binding.coachPose.show(snap.exercise)
            coachCue.text = snap.exercise.startCue
        }
        if (show == coachShowing) return
        coachShowing = show
        binding.coachCard.visibility = if (show) View.VISIBLE else View.GONE
        // One voice: while the figure is up it carries the cue, so the pill stands down. INVISIBLE
        // rather than GONE, because the card hangs off the pill's bottom edge.
        binding.statusRow.visibility = if (show) View.INVISIBLE else View.VISIBLE
    }

    /**
     * REC in its three states: counting down, filming, and neither.
     *
     * The countdown is what a tap buys — not a recording. Filming used to begin on the tap
     * itself, so every clip opened on the athlete still at the phone, and nothing on screen had
     * said it was about to. Tapping again during the count calls it off, because a countdown you
     * cannot stop is a recording you cannot refuse; that is also why the second tap cancels
     * rather than restarting, which is what the view would do on its own.
     */
    private fun toggleRecording() {
        if (binding.countdown.isRunning) {
            binding.countdown.cancel()
            renderChips()
            toast("Recording cancelled")
            return
        }
        if (video.isRecording) {
            video.stop()
            renderChips()
            return
        }
        if (video.useCase == null) {
            toast("Recording is not available on this camera")
            return
        }
        binding.countdown.start { beginRecording() }
        renderChips()
    }

    /** The far side of the countdown. Nothing else calls this. */
    private fun beginRecording() {
        val started = video.start { name ->
            renderChips()
            toast(if (name != null) "Saved $name to Movies/Cindy" else "Recording failed")
        }
        if (!started) toast("Could not start recording")
        buzz(40L)
        renderChips()
    }

    /**
     * Shows where to stand, then starts the setup check.
     *
     * Placement is the one thing the athlete has to get right before the camera can help them,
     * and the setup check can only report it *after* they are already in shot getting it wrong —
     * "Can't see your ankles" arrives too late to be advice. So it is offered first, once, and
     * then stays out of the way: [KEY_PLACEMENT_SEEN] suppresses it for someone who has read it,
     * and the same diagram lives permanently in the help screen for when they want it back.
     */
    private fun showPlacementGuide(onContinue: () -> Unit) {
        if (prefs().getBoolean(KEY_PLACEMENT_SEEN, false)) {
            onContinue()
            return
        }
        val sheet = CindySheet(
            this,
            title = "Where to stand",
            subtitle = "The one thing you have to get right before the camera can help."
        )

        sheet.add(PlacementGuideView(this).apply {
            setBackgroundResource(R.drawable.glass_card_small)
            setPadding(dp(12), dp(14), dp(12), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(200)
            )
        })

        // Three facts, one line each, rather than a paragraph nobody reads on the way to a bar.
        listOf(
            R.drawable.ic_phone_stand to "Stand the phone up rather than laying it flat.",
            R.drawable.ic_frame to "Keep your head and your feet both in shot.",
            R.drawable.ic_dont_move to
                "Then leave it there — moving it mid-workout resets what it has learned."
        ).forEachIndexed { index, (icon, text) ->
            sheet.add(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, if (index == 0) dp(18) else dp(13), 0, 0)
                addView(ImageView(context).apply {
                    setImageResource(icon)
                    imageTintList = ColorStateList.valueOf(
                        getColor(
                            if (icon == R.drawable.ic_dont_move) R.color.state_caution
                            else R.color.label_tertiary
                        )
                    )
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }, LinearLayout.LayoutParams(dp(17), dp(17)).apply { topMargin = dp(2) })
                addView(styledText(R.style.Cindy_Callout, text).apply {
                    setTextColor(getColor(R.color.label_body))
                    setPadding(dp(11), 0, 0, 0)
                })
            })
        }

        var dontAskAgain = false
        sheet.toggle("Don't show this again", checked = false) { dontAskAgain = it }

        sheet.actions(
            primary = "START SETUP",
            onPrimary = {
                if (dontAskAgain) prefs().edit().putBoolean(KEY_PLACEMENT_SEEN, true).apply()
                onContinue()
            },
            secondary = "NOT NOW",
            onSecondary = {}
        ).show()
    }

    /**
     * Picks up a movement change made in [MenuActivity], which is the only place it can be made.
     *
     * The picker moved off this screen with the chip that opened it, so the profile can now
     * change while this activity is stopped. [WorkoutEngine.profile] is immutable for the life of
     * an engine — deliberately, so a half-scored workout can never be two prescriptions at once —
     * which makes the response a rebuild rather than a mutation.
     *
     * Refused outright while a workout is live. The menu already declines to open the picker in
     * that state; this is the same rule enforced where the score actually lives, because the
     * clock could have been started from a notification or a second window between the two.
     */
    private fun syncMovements() {
        if (inWorkout()) return
        val chosen = profile.movements
        val current = synchronized(engineLock) { engine.profile }
        if (chosen == current) return
        synchronized(engineLock) { engine = WorkoutEngine(profile = chosen) }
        apply(runEngine { RepEvent.NONE })
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

    override fun onResume() {
        super.onResume()
        syncMovements()
    }

    override fun onPause() {
        super.onPause()
        // The three seconds were for walking to the bar, not for leaving the app.
        if (binding.countdown.isRunning) {
            binding.countdown.cancel()
            renderChips()
        }
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
