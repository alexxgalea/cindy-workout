package com.cindy.tracker

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.Locale
import kotlin.math.abs

/**
 * Offline regression runner for labelled exercise clips.
 *
 * It deliberately runs on an Android emulator or device: PoseDetector is the production MoveNet
 * implementation, including its model asset, bitmap preprocessing and ROI tracking. The same
 * WorkoutEngine instance that the activity uses receives every resulting keypoint frame.
 *
 * Run it only when video fixtures have been provisioned locally:
 *   ./gradlew videoRegressionTest -PcindyVideoRegression=true
 *
 * A missing opt-in flag, catalog, or fixture produces a JUnit skip with an explicit message. It
 * is never presented as a successful regression run.
 */
@RunWith(AndroidJUnit4::class)
class VideoRegressionInstrumentationTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val testContext: Context = instrumentation.context
    private val appContext: Context = instrumentation.targetContext
    private val args get() = InstrumentationRegistry.getArguments()

    @Test
    fun labelledVideosMatchProductionCountingLogic() {
        assumeTrue(
            "SKIPPED: video fixtures are opt-in; run with -PcindyVideoRegression=true",
            args.getString("videoRegression") == "true"
        )
        assumeTrue(
            "SKIPPED: native-frame decoding requires Android API 28 or newer",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
        )

        val scenarios = CATALOGS.flatMap(::loadCatalog)
        assumeTrue(
            "SKIPPED: no video scenarios found in tests/scenarios. Generate or add fixture labels first.",
            scenarios.isNotEmpty()
        )

        val missing = scenarios.filterNot { assetExists(assetPathFor(it.video)) }
        assumeTrue(
            "SKIPPED: ${missing.size} declared video fixture(s) are unavailable: " +
                missing.take(5).joinToString { it.video } +
                ". Provision them outside git, then retry.",
            missing.isEmpty()
        )

        val reports = scenarios.map(::runScenario)
        val output = writeReports(reports)
        Log.i(TAG, "Video regression reports: ${output.absolutePath}")

        val failures = reports.flatMap { report -> report.failures.map { "${report.id}: $it" } }
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    private fun runScenario(scenario: Scenario): ScenarioReport {
        val errors = mutableListOf<String>()
        val inferred = inferVideo(scenario, errors)
        if (inferred.isEmpty()) {
            return ScenarioReport(scenario.id, scenario.expectedReps, 0, null, emptyList(), emptyList(), errors)
        }

        compareGoldenIfPresent(scenario, inferred, errors)
        if (args.getString("recordGoldens") == "true") writeGolden(scenario, inferred)

        val exercise = when (scenario.exercise.lowercase(Locale.US)) {
            "pullup", "pull-up", "pullups", "pull-ups" -> Exercise.PULLUP
            "pushup", "push-up", "pushups", "push-ups" -> Exercise.PUSHUP
            "squat", "squats" -> Exercise.SQUAT
            else -> {
                errors += "Unsupported exercise '${scenario.exercise}'"
                return ScenarioReport(scenario.id, scenario.expectedReps, 0, null, emptyList(), emptyList(), errors)
            }
        }

        // Setup is validated separately from score comparison. Dataset labels normally include
        // every movement in a clip, while the phone deliberately does not score its two setup
        // reps. A scoring engine therefore sees the complete labelled clip; a second engine
        // verifies that the same clip is framed/calibratable and that onFrame is blocked during
        // setup.
        val setupEngine = WorkoutEngine(fixedExercise = exercise)
        setupEngine.beginSetup()
        configureManualBar(setupEngine, scenario, inferred.first())
        var setup: Setup? = null
        inferred.forEach { frame ->
            val before = setupEngine.reps
            val blocked = setupEngine.onFrame(frame.keypoints, frame.timestampMs, frame.trackingStable)
            if (blocked != RepEvent.NONE || setupEngine.reps != before) {
                errors += "workout count changed before setup completed at ${frame.timestampMs}ms"
            }
            setup = setupEngine.onSetupFrame(frame.keypoints, frame.timestampMs, frame.trackingStable)
        }
        assertExpectedSetup(scenario.expectedSetup, setup?.stage, errors)

        val engine = WorkoutEngine(fixedExercise = exercise)
        configureManualBar(engine, scenario, inferred.first())
        val frames = mutableListOf<FrameReport>()
        val countTimes = mutableListOf<Long>()
        inferred.forEach { frame ->
            val event = engine.onFrame(frame.keypoints, frame.timestampMs, frame.trackingStable)
            val d = engine.diagnostics
            if (event != RepEvent.NONE) {
                countTimes += frame.timestampMs
                if (!d.scoringConfidenceAdequate) errors += "count at ${frame.timestampMs}ms with inadequate confidence"
                if (exercise == Exercise.PULLUP) {
                    if (!d.identityStable) errors += "pull-up count at ${frame.timestampMs}ms without stable identity"
                    if (!d.barGateOpen) errors += "pull-up count at ${frame.timestampMs}ms outside bar zone"
                    if (!d.deadHangSinceLastRep || !d.resetBelowBarSeen) {
                        errors += "pull-up count at ${frame.timestampMs}ms without a fresh reset dead hang"
                    }
                    if (!d.headAboveBar) errors += "pull-up count at ${frame.timestampMs}ms before head crossed bar"
                }
            }
            frames += FrameReport(
                timestampMs = frame.timestampMs,
                event = event.name,
                count = engine.reps,
                state = engine.countingState,
                minimumConfidence = d.minimumConfidence,
                confidenceAdequate = d.scoringConfidenceAdequate,
                barGateOpen = d.barGateOpen,
                headAboveBar = d.headAboveBar,
                resetSeen = d.resetBelowBarSeen,
                rejection = d.rejectionReason
            )
        }

        if (engine.reps != scenario.expectedReps) {
            errors += "expected ${scenario.expectedReps} reps, observed ${engine.reps}"
        }
        scenario.expectedCountingState?.let { expected ->
            if (engine.countingState != expected.lowercase(Locale.US)) {
                errors += "expected final state '$expected', observed '${engine.countingState}'"
            }
        }
        assertExpectedEvents(scenario, countTimes, errors)
        return ScenarioReport(
            id = scenario.id,
            expectedReps = scenario.expectedReps,
            observedReps = engine.reps,
            setup = setup?.stage?.name?.lowercase(Locale.US),
            countTimes = countTimes,
            frames = frames,
            failures = errors,
            tags = scenario.tags
        )
    }

    private fun configureManualBar(engine: WorkoutEngine, scenario: Scenario, first: InferredFrame) {
        scenario.bar?.takeIf { it.mode.equals("manual", ignoreCase = true) }?.let { bar ->
            engine.configureManualBar(
                yNormalized = bar.yNormalized,
                xMinNormalized = bar.xMinNormalized,
                xMaxNormalized = bar.xMaxNormalized,
                frameWidth = first.width,
                frameHeight = first.height
            )
        }
    }

    private fun inferVideo(scenario: Scenario, errors: MutableList<String>): List<InferredFrame> {
        val asset = assetPathFor(scenario.video)
        val localVideo = copyAssetToCache(asset)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(localVideo.absolutePath)
            val frameCount = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
                ?.toIntOrNull()
                ?: error("Video has no frame-count metadata; re-encode it with a native frame index")
            val fps = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toFloatOrNull()
                ?: error("Video has no FPS metadata; re-encode it with a native frame rate")
            require(frameCount > 0) { "Video has no frames" }
            require(fps > 0f) { "Video has invalid FPS '$fps'" }

            val model = when (scenario.model?.lowercase(Locale.US)) {
                null, "thunder", "movenet_thunder.tflite" -> PoseDetector.THUNDER
                "lightning", "movenet_lightning.tflite" -> PoseDetector.LIGHTNING
                else -> error("Unsupported production model '${scenario.model}'")
            }
            val detector = PoseDetector(appContext, model)
            try {
                buildList(frameCount) {
                    for (index in 0 until frameCount) {
                        val bitmap = retriever.getFrameAtIndex(index)
                            ?: error("Could not decode native frame $index")
                        try {
                            add(
                                InferredFrame(
                                    timestampMs = (index * 1_000f / fps).toLong(),
                                    width = bitmap.width,
                                    height = bitmap.height,
                                    trackingStable = detector.tracking,
                                    keypoints = detector.detect(bitmap)
                                )
                            )
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
            } finally {
                detector.close()
            }
        } catch (t: Throwable) {
            errors += "inference failed: ${t.message ?: t.javaClass.simpleName}"
            emptyList()
        } finally {
            retriever.release()
        }
    }

    private fun assertExpectedSetup(expected: String?, actual: SetupStage?, errors: MutableList<String>) {
        if (expected == null) return
        val accepted = when (expected.lowercase(Locale.US)) {
            "valid" -> actual == SetupStage.MOVING || actual == SetupStage.READY
            "ready" -> actual == SetupStage.READY
            "framing", "invalid" -> actual == SetupStage.FRAMING
            "poor", "paused", "pause" -> actual == SetupStage.POOR
            else -> {
                errors += "unsupported expectedSetup '$expected'"
                return
            }
        }
        if (!accepted) errors += "expected setup '$expected', observed '${actual?.name?.lowercase(Locale.US)}'"
    }

    private fun assertExpectedEvents(scenario: Scenario, observed: List<Long>, errors: MutableList<String>) {
        if (scenario.expectedRepEventsMs.isEmpty()) return
        if (scenario.expectedRepEventsMs.size != observed.size) {
            errors += "expected ${scenario.expectedRepEventsMs.size} count events, observed ${observed.size}"
            return
        }
        scenario.expectedRepEventsMs.zip(observed).forEachIndexed { index, (expected, actual) ->
            if (abs(expected - actual) > scenario.eventToleranceMs) {
                errors += "event ${index + 1}: expected about ${expected}ms, observed ${actual}ms"
            }
        }
    }

    private fun compareGoldenIfPresent(
        scenario: Scenario,
        inferred: List<InferredFrame>,
        errors: MutableList<String>
    ) {
        val asset = "golden/pose_keypoints/${scenario.id}.json"
        if (!assetExists(asset)) return
        val frames = JSONObject(readAsset(asset)).getJSONArray("frames")
        if (frames.length() != inferred.size) {
            errors += "golden has ${frames.length()} frames; inference produced ${inferred.size}"
            return
        }
        for (index in inferred.indices) {
            val expected = frames.getJSONObject(index).getJSONArray("keypoints")
            if (expected.length() != KP.COUNT) {
                errors += "golden frame $index has ${expected.length()} keypoints, expected ${KP.COUNT}"
                continue
            }
            for (kpIndex in 0 until KP.COUNT) {
                val stored = expected.getJSONObject(kpIndex)
                val actual = inferred[index].keypoints[kpIndex]
                val positionChanged = abs(stored.getDouble("x").toFloat() - actual.x) > GOLDEN_POSITION_TOLERANCE ||
                    abs(stored.getDouble("y").toFloat() - actual.y) > GOLDEN_POSITION_TOLERANCE
                val confidenceChanged = abs(stored.getDouble("score").toFloat() - actual.score) > GOLDEN_SCORE_TOLERANCE
                if (positionChanged || confidenceChanged) {
                    errors += "golden differs at frame $index, keypoint $kpIndex"
                    return
                }
            }
        }
    }

    private fun writeGolden(scenario: Scenario, inferred: List<InferredFrame>) {
        val root = JSONObject().put("scenarioId", scenario.id).put("frames", JSONArray())
        val frames = root.getJSONArray("frames")
        inferred.forEach { frame ->
            frames.put(JSONObject().apply {
                put("timestampMs", frame.timestampMs)
                put("keypoints", keypointsJson(frame.keypoints))
            })
        }
        val file = File(externalRoot("goldens"), "${scenario.id}.json")
        file.parentFile?.mkdirs()
        file.writeText(root.toString(2))
    }

    private fun writeReports(reports: List<ScenarioReport>): File {
        val root = JSONObject().put("scenarios", JSONArray())
        val scenarios = root.getJSONArray("scenarios")
        reports.forEach { report ->
            scenarios.put(JSONObject().apply {
                put("id", report.id)
                put("expectedReps", report.expectedReps)
                put("observedReps", report.observedReps)
                put("setup", report.setup)
                put("countTimestampsMs", JSONArray(report.countTimes))
                put("tags", JSONArray(report.tags))
                put("failures", JSONArray(report.failures))
                put("frames", JSONArray().apply {
                    report.frames.forEach { frame -> put(frame.toJson()) }
                })
            })
        }
        val rootDir = externalRoot("reports")
        rootDir.mkdirs()
        val json = File(rootDir, "video-regression.json")
        json.writeText(root.toString(2))
        File(rootDir, "video-regression.csv").writeText(buildString {
            appendLine(
                "id,expected_reps,observed_reps,setup,count_timestamps_ms,tags,failures," +
                    "frame_timestamp_ms,event,count,state,minimum_confidence,confidence_adequate," +
                    "bar_gate_open,head_above_bar,reset_seen,rejection_reason"
            )
            reports.forEach { report ->
                val rows = report.frames.ifEmpty {
                    listOf(FrameReport(0L, "", 0, "", 0f, false, false, false, false, null))
                }
                rows.forEach { frame ->
                    appendLine(
                        listOf(
                            report.id,
                            report.expectedReps.toString(),
                            report.observedReps.toString(),
                            report.setup.orEmpty(),
                            report.countTimes.joinToString("|"),
                            report.tags.joinToString("|"),
                            report.failures.joinToString(" | "),
                            frame.timestampMs.toString(),
                            frame.event,
                            frame.count.toString(),
                            frame.state,
                            frame.minimumConfidence.toString(),
                            frame.confidenceAdequate.toString(),
                            frame.barGateOpen.toString(),
                            frame.headAboveBar.toString(),
                            frame.resetSeen.toString(),
                            frame.rejection.orEmpty()
                        ).joinToString(",") { csv(it) }
                    )
                }
            }
        })
        return rootDir
    }

    private fun FrameReport.toJson() = JSONObject().apply {
        put("timestampMs", timestampMs)
        put("event", event)
        put("count", count)
        put("state", state)
        put("minimumConfidence", minimumConfidence)
        put("confidenceAdequate", confidenceAdequate)
        put("barGateOpen", barGateOpen)
        put("headAboveBar", headAboveBar)
        put("resetSeen", resetSeen)
        put("rejection", rejection)
    }

    private fun keypointsJson(keypoints: Array<Keypoint>) = JSONArray().apply {
        keypoints.forEach { point ->
            put(JSONObject().put("x", point.x).put("y", point.y).put("score", point.score))
        }
    }

    private fun loadCatalog(asset: String): List<Scenario> {
        if (!assetExists(asset)) return emptyList()
        val root = JSONObject(readAsset(asset))
        val entries = root.optJSONArray("scenarios") ?: JSONArray()
        return List(entries.length()) { index -> entries.getJSONObject(index).toScenario() }
    }

    private fun JSONObject.toScenario(): Scenario {
        val bar = optJSONObject("bar")?.let {
            val mode = it.optString("mode", "auto")
            Bar(
                mode = mode,
                yNormalized = if (mode.equals("manual", ignoreCase = true)) {
                    it.getDouble("yNormalized").toFloat()
                } else 0f,
                xMinNormalized = if (mode.equals("manual", ignoreCase = true)) {
                    it.getDouble("xMinNormalized").toFloat()
                } else 0f,
                xMaxNormalized = if (mode.equals("manual", ignoreCase = true)) {
                    it.getDouble("xMaxNormalized").toFloat()
                } else 0f
            )
        }
        val events = optJSONArray("expectedRepEventsMs")?.let { values ->
            List(values.length()) { values.getLong(it) }
        }.orEmpty()
        val tags = optJSONArray("tags")?.let { values ->
            List(values.length()) { values.getString(it) }
        }.orEmpty()
        return Scenario(
            id = getString("id"),
            video = getString("video"),
            exercise = getString("exercise"),
            expectedReps = getInt("expectedReps"),
            expectedSetup = optString("expectedSetup").takeIf { it.isNotBlank() },
            expectedCountingState = optString("expectedCountingState").takeIf { it.isNotBlank() },
            bar = bar,
            tags = tags,
            expectedRepEventsMs = events,
            eventToleranceMs = optLong("eventToleranceMs", DEFAULT_EVENT_TOLERANCE_MS),
            model = optString("model").takeIf { it.isNotBlank() }
        )
    }

    private fun externalRoot(child: String): File {
        val root = appContext.getExternalFilesDir("video-regression") ?: appContext.filesDir
        return File(root, child)
    }

    private fun copyAssetToCache(asset: String): File {
        val target = File(appContext.cacheDir, "video-regression/${asset.substringAfterLast('/')}")
        target.parentFile?.mkdirs()
        testContext.assets.open(asset).use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return target
    }

    private fun assetExists(asset: String): Boolean = try {
        testContext.assets.open(asset).close()
        true
    } catch (_: Exception) {
        false
    }

    private fun readAsset(asset: String): String = testContext.assets.open(asset).bufferedReader().use { it.readText() }

    private fun assetPathFor(video: String): String = video.removePrefix("tests/")

    private fun csv(value: String): String = "\"${value.replace("\"", "\"\"")}\""

    private data class Scenario(
        val id: String,
        val video: String,
        val exercise: String,
        val expectedReps: Int,
        val expectedSetup: String?,
        val expectedCountingState: String?,
        val bar: Bar?,
        val tags: List<String>,
        val expectedRepEventsMs: List<Long>,
        val eventToleranceMs: Long,
        val model: String?
    )

    private data class Bar(
        val mode: String,
        val yNormalized: Float,
        val xMinNormalized: Float,
        val xMaxNormalized: Float
    )

    private data class InferredFrame(
        val timestampMs: Long,
        val width: Int,
        val height: Int,
        val trackingStable: Boolean,
        val keypoints: Array<Keypoint>
    )

    private data class FrameReport(
        val timestampMs: Long,
        val event: String,
        val count: Int,
        val state: String,
        val minimumConfidence: Float,
        val confidenceAdequate: Boolean,
        val barGateOpen: Boolean,
        val headAboveBar: Boolean,
        val resetSeen: Boolean,
        val rejection: String?
    )

    private data class ScenarioReport(
        val id: String,
        val expectedReps: Int,
        val observedReps: Int,
        val setup: String?,
        val countTimes: List<Long>,
        val frames: List<FrameReport>,
        val failures: List<String>,
        val tags: List<String> = emptyList()
    )

    private companion object {
        const val TAG = "CindyVideoRegression"
        const val DEFAULT_EVENT_TOLERANCE_MS = 500L
        const val GOLDEN_POSITION_TOLERANCE = 12f
        const val GOLDEN_SCORE_TOLERANCE = 0.15f
        val CATALOGS = listOf(
            "scenarios/infiniterep.json",
            "scenarios/repcount.json",
            "scenarios/local_regressions.json"
        )
    }
}
