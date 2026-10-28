package com.cindy.tracker

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The trace a debug build writes must be one the desktop replay can read back exactly. This test
 * runs a whole Cindy session through the real engine, setup included, writes it the way
 * MainActivity does, and leaves the file at app/build/engine-trace-sample.csv for
 * `tools/video_regression/replay_trace.py` to replay.
 */
class EngineTraceTest {

    private var clock = 0L
    private val engine = WorkoutEngine()
    private lateinit var trace: EngineTrace

    private fun row(keypoints: Array<Keypoint>, setup: Setup?, event: RepEvent?) = EngineTrace.Row(
        captureNanos = clock * 1_000_000L,
        engineMs = clock,
        convertMs = 1,
        prepMs = 2,
        inferMs = 40,
        captureAgeMs = 90,
        tracking = true,
        softGain = 1f,
        thermal = 0,
        frameW = 480,
        frameH = 640,
        keypoints = keypoints,
        setupStage = setup?.stage?.name,
        exercise = engine.exercise,
        reps = setup?.reps ?: engine.reps,
        event = event,
        phase = engine.countingState,
        signal = engine.signal,
        rejection = engine.diagnostics.rejectionReason,
        profile = engine.profile,
        smartSquats = engine.smartSquats
    )

    private fun setupHold(pose: Array<Keypoint>, frames: Int = 10): Setup {
        var last: Setup? = null
        repeat(frames) {
            last = engine.onSetupFrame(pose, clock)
            trace.frame(row(pose, last, null))
            clock += 100L
        }
        return last!!
    }

    private fun hold(pose: Array<Keypoint>, frames: Int = 10) = repeat(frames) {
        val event = engine.onFrame(pose, clock)
        trace.frame(row(pose, null, event))
        clock += 100L
    }

    @Test
    fun `a whole session writes rows the replay can read back`() {
        val dir = Files.createTempDirectory("trace").toFile()
        trace = EngineTrace(dir)
        engine.beginSetup()
        var setup = setupHold(PoseFixtures.pullup(170f))
        repeat(2) {
            setupHold(PoseFixtures.pullup(170f))
            setup = setupHold(PoseFixtures.pullup(60f))
        }
        assertEquals(SetupStage.READY, setup.stage)
        engine.finishSetup()
        repeat(5) {
            hold(PoseFixtures.pullup(170f))
            hold(PoseFixtures.pullup(60f))
        }
        hold(PoseFixtures.pullup(170f))
        repeat(10) {
            hold(PoseFixtures.pushup(170f))
            hold(PoseFixtures.pushup(70f))
        }
        hold(PoseFixtures.pushup(170f))
        repeat(3) {
            hold(PoseFixtures.squat(175f))
            hold(PoseFixtures.squat(70f))
        }
        hold(PoseFixtures.squat(175f))
        trace.close()

        val lines = trace.file!!.readLines()
        val columns = EngineTrace.HEADER.split(',').size
        assertEquals(EngineTrace.HEADER, lines.first())
        lines.drop(1).forEach { assertEquals(it, columns, it.split(',').size) }
        assertTrue(lines.any { it.startsWith("setup,") })
        assertEquals(Exercise.SQUAT, engine.exercise)

        val root = repositoryRoot()
        trace.file!!.copyTo(File(root, "app/build/engine-trace-sample.csv"), overwrite = true)
    }

    private fun repositoryRoot(): File {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        return dir ?: error("Could not locate the repository root")
    }
}
