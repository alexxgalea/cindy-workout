package com.cindy.tracker

import java.io.File
import org.junit.Test

/**
 * Emits the reference trace that the Python port in tools/video_regression is checked against.
 *
 * The offline harness re-implements RepCounter, BarZone and WorkoutEngine in Python so counting
 * bugs can be reproduced on a desktop against real video. Two implementations of the same rules
 * drift, and a harness that has quietly stopped agreeing with the phone is worse than no harness
 * at all — it produces confident, wrong verdicts.
 *
 * So this test replays tests/parity/plan.csv through the production engine and writes every
 * frame's decision to tests/parity/trace_jvm.csv. `parity_check.py` replays the same plan through
 * the port and diffs the two row for row, which localises any divergence to a single frame rather
 * than to "the counts disagree".
 *
 * It asserts nothing itself: it is a generator, and the Python side owns the comparison.
 */
class EngineParityTraceTest {

    @Test
    fun `writes the reference trace for the python port`() {
        val root = repositoryRoot()
        val plan = File(root, "tests/parity/plan.csv")
        check(plan.isFile) { "Missing parity plan at ${plan.absolutePath}" }

        val rows = plan.readLines().drop(1).filter { it.isNotBlank() }.map { it.split(",") }
        val output = StringBuilder(HEADER).append('\n')

        rows.groupBy { it[TRACE_ID] }.forEach { (traceId, steps) ->
            val exercise = when (steps.first()[EXERCISE]) {
                "pullup" -> Exercise.PULLUP
                "pushup" -> Exercise.PUSHUP
                "squat" -> Exercise.SQUAT
                else -> error("Unknown exercise in $traceId")
            }
            val pull = PullVariant.entries.first { it.name == steps.first()[PULL] }
            val engine = WorkoutEngine(
                fixedExercise = exercise,
                profile = CindyProfile(pull = pull)
            )
            steps.forEach { step ->
                val angle = step[ANGLE].toFloat()
                val now = step[STEP_MS].toLong() * step[STEP].toLong()
                val keypoints = when (step[BUILDER]) {
                    "pullup" -> PoseFixtures.pullup(angle)
                    "pushup" -> PoseFixtures.pushup(angle)
                    "squat" -> PoseFixtures.squat(angle)
                    "bandsetup" -> PoseFixtures.bandSetup()
                    else -> error("Unknown builder in $traceId")
                }
                val event = engine.onFrame(keypoints, now)
                val d = engine.diagnostics
                output.append(
                    listOf(
                        traceId,
                        step[STEP],
                        now.toString(),
                        step[ANGLE],
                        // Guards the fixture geometry itself, so a divergence in the synthetic
                        // body is distinguishable from a divergence in the counting rules.
                        round(keypoints.sumOf { (it.x + it.y).toDouble() }),
                        event.name,
                        engine.reps.toString(),
                        engine.countingState,
                        round(engine.signal.toDouble()),
                        round(engine.learnedRange.toDouble()),
                        engine.calibrated.toString(),
                        engine.hint,
                        round(d.minimumConfidence.toDouble()),
                        d.scoringConfidenceAdequate.toString(),
                        d.barGateOpen.toString(),
                        d.headAboveBar.toString(),
                        d.resetBelowBarSeen.toString(),
                        d.rejectionReason.orEmpty()
                    ).joinToString(",") { field -> "\"" + field.replace("\"", "\"\"") + "\"" }
                ).append('\n')
            }
        }

        val target = File(root, "tests/parity/trace_jvm.csv")
        target.parentFile?.mkdirs()
        target.writeText(output.toString())
        println("Parity trace written to ${target.absolutePath} (${rows.size} frames)")
    }

    /** NaN has no stable cross-language spelling, so it is normalised here. */
    private fun round(value: Double): String =
        if (value.isNaN()) "nan" else String.format(java.util.Locale.US, "%.3f", value)

    /** Unit tests run with the module as the working directory; walk up to the settings file. */
    private fun repositoryRoot(): File {
        val start = System.getProperty("user.dir") ?: "."
        var dir: File? = File(start).absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        return dir ?: error("Could not locate the repository root from $start")
    }

    private companion object {
        const val TRACE_ID = 0
        const val EXERCISE = 1
        const val BUILDER = 2
        const val STEP_MS = 3
        const val STEP = 4
        const val ANGLE = 5
        const val PULL = 6
        const val HEADER = "traceId,step,tMs,angle,kpSum,event,count,state,signal,learnedRange," +
            "calibrated,hint,minConfidence,confidenceAdequate,barGateOpen,headAboveBar," +
            "resetSeen,rejection"
    }
}
