package com.cindy.tracker

import java.io.File
import org.junit.Test

/**
 * Emits the reference trace that the Python recogniser in tools/video_regression is checked against.
 *
 * The harness runs the same position rules over films as the phone runs on the camera, in Python.
 * Two implementations of the same rules drift, and a harness that has quietly stopped agreeing
 * with the phone gives confident, wrong verdicts about a film.
 *
 * So this test replays tests/parity/recognition_plan.csv, synthetic sequences that cross from one
 * position to another, through [Recogniser] and writes every frame's position to
 * tests/parity/recognition_trace_jvm.csv. `recognition_parity_check.py` replays the same plan
 * through the twin and diffs the two row for row. It is separate from the counting engine's plan
 * and trace (EngineParityTraceTest), which recognition never touches.
 *
 * It asserts nothing itself: it is a generator, and the Python side owns the comparison.
 */
class RecognitionParityTraceTest {

    @Test
    fun `writes the reference trace for the python recogniser`() {
        val root = repositoryRoot()
        val plan = File(root, "tests/parity/recognition_plan.csv")
        check(plan.isFile) { "Missing recognition plan at ${plan.absolutePath}" }

        val rows = plan.readLines().drop(1).filter { it.isNotBlank() }.map { it.split(",") }
        val output = StringBuilder(HEADER).append('\n')

        rows.groupBy { it[TRACE_ID] }.forEach { (traceId, steps) ->
            val recogniser = Recogniser()
            steps.forEach { step ->
                val angle = step[ANGLE].toFloat()
                val now = step[T_MS].toLong()
                val keypoints = when (step[BUILDER]) {
                    "pullup" -> PoseFixtures.pullup(angle)
                    "pushup" -> PoseFixtures.pushup(angle)
                    "squat" -> PoseFixtures.squat(angle)
                    "empty" -> PoseFixtures.empty()
                    "onthefloor" -> PoseFixtures.onTheFloor()
                    "hangwithlegs" -> PoseFixtures.hangWithLegs(angle)
                    "kneelingup" -> PoseFixtures.kneelingUp(angle)
                    "headonplank" -> PoseFixtures.headOnPlank()
                    "leaningsquat" -> PoseFixtures.leaningSquat(angle)
                    "walking" -> PoseFixtures.walking(angle)
                    else -> error("Unknown builder in $traceId")
                }
                val recognition = recogniser.onFrame(keypoints, now, step[STABLE] == "true")
                output.append(
                    listOf(
                        traceId,
                        step[STEP],
                        now.toString(),
                        step[BUILDER],
                        step[ANGLE],
                        step[STABLE],
                        // Guards the fixture geometry itself, so a divergence in the synthetic
                        // body is distinguishable from a divergence in the position rules.
                        round(keypoints.sumOf { (it.x + it.y).toDouble() }),
                        recognition.position.id
                    ).joinToString(",") { field -> "\"" + field.replace("\"", "\"\"") + "\"" }
                ).append('\n')
            }
        }

        val target = File(root, "tests/parity/recognition_trace_jvm.csv")
        target.parentFile?.mkdirs()
        target.writeText(output.toString())
        println("Recognition trace written to ${target.absolutePath} (${rows.size} frames)")
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
        const val STEP = 1
        const val T_MS = 2
        const val BUILDER = 3
        const val ANGLE = 4
        const val STABLE = 5
        const val HEADER = "traceId,step,tMs,builder,angle,stable,kpSum,position"
    }
}
