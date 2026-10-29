package com.cindy.tracker

import java.io.File
import kotlin.math.abs
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Calibration that never finished, though the athlete was doing pull-ups on the wall bars.
 *
 * Each tests/traces/calibration_stuck_*.csv is the setup part of a real session, written by a debug
 * build on a Huawei P40: every frame the engine was given, from the first, until a few seconds after
 * the fixed engine would have calibrated. The screen recordings show the athlete hanging and pulling
 * from the first seconds on; the phone stayed at 0 of 2 calibration reps and said "Get on the bar"
 * until the athlete gave up or skipped the setup.
 *
 * What went wrong is the same in all four: the bar was learned from a hang whose two wrists were
 * a few pixels apart, so the zone it allowed was a sliver, and a normal grip fell outside it. In
 * two of them the hang was at the frame's left edge, so the bar was learned where the athlete was
 * not. Nothing healed it, because the only recovery needed the athlete to change size in the frame.
 *
 * calibration_ok_1637.csv is a session that calibrated, as the control: the fix must not change it.
 */
class StuckCalibrationTest {

    @Test
    fun `a bar learned from a sliver of a grip does not stop the athlete calibrating`() {
        listOf(
            "calibration_stuck_1635.csv",
            "calibration_stuck_1643.csv",
            "calibration_stuck_1644.csv",
            "calibration_stuck_1651.csv"
        ).forEach { name ->
            val trace = Trace.read(name)
            val calibratedAt = calibratedAt(trace)
            assertNotNull(
                "$name: still ${trace.lastStage} at ${trace.lastMs} ms of a session in which the " +
                    "athlete was pulling up, last said \"${trace.lastHint}\"",
                calibratedAt
            )
        }
    }

    /** The phone itself calibrated this one at 24.3 s, and that must stay as it was. */
    @Test
    fun `a session that calibrated still calibrates at the same moment`() {
        val calibratedAt = calibratedAt(Trace.read("calibration_ok_1637.csv"))
        assertNotNull(calibratedAt)
        assertTrue("calibrated at $calibratedAt ms, the phone did at 24300", abs(calibratedAt!! - 24_300L) <= 300L)
    }

    /** Replays [trace] as the app does: setup frames, with a recalibration where one happened. */
    private fun calibratedAt(trace: Trace): Long? {
        val engine = WorkoutEngine()
        engine.beginSetup()
        var at: Long? = null
        trace.rows.forEach { row ->
            if (row.recalibrate) {
                engine.recalibrate()
                return@forEach
            }
            val setup = engine.onSetupFrame(row.keypoints!!, row.ms, row.tracking)
            trace.lastStage = setup.stage
            trace.lastMs = row.ms
            trace.lastHint = engine.hint
            if (at == null && setup.stage == SetupStage.READY && setup.reps >= 2) at = row.ms
        }
        return at
    }

    private class Row(val ms: Long, val tracking: Boolean, val keypoints: Array<Keypoint>?) {
        val recalibrate get() = keypoints == null
    }

    private class Trace(val rows: List<Row>) {
        var lastStage: SetupStage? = null
        var lastMs = 0L
        var lastHint = ""

        companion object {
            fun read(name: String): Trace {
                val file = File(repositoryRoot(), "tests/traces/$name")
                val rows = file.readLines().drop(1).filter { it.isNotBlank() }.map { line ->
                    val f = line.split(',')
                    val ms = f[1].toLong()
                    if (f[0] == "RECALIBRATE") {
                        Row(ms, false, null)
                    } else {
                        val keypoints = Array(17) { i ->
                            Keypoint(f[3 + 3 * i].toFloat(), f[4 + 3 * i].toFloat(), f[5 + 3 * i].toFloat())
                        }
                        Row(ms, f[2] == "1", keypoints)
                    }
                }
                return Trace(rows)
            }

            private fun repositoryRoot(): File {
                var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
                while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
                return dir ?: error("Could not locate the repository root")
            }
        }
    }
}
