package com.cindy.tracker

import java.io.File
import java.util.Locale
import org.junit.Test

/**
 * Emits the reference Freestyle trace that the Python twin in tools/video_regression is checked
 * against (`freestyle_parity_check.py`).
 *
 * Every trace of tests/parity/recognition_plan.csv and tests/parity/freestyle_plan.csv is run as a
 * Freestyle session through [FreestyleEngine]: START at the first frame, then every frame, then
 * STOP at the last. Per frame it writes what the scoreboard reads (figure, movement, total, line,
 * whether - and + may act), the reps banked per movement so far and what the voice was to say, to
 * tests/parity/freestyle_trace_jvm.csv. At STOP it writes what was filed and the derived sets and
 * gaps, to tests/parity/freestyle_sets_jvm.csv.
 *
 * The films are the same, from keypoints the Python harness dumped to tests/parity/films (local,
 * never committed: they are the owner's films). Each is written to freestyle_film_trace_jvm.csv
 * and freestyle_film_sets_jvm.csv, also local. With no dumps, the film files are not written.
 *
 * The counting engine's trace (EngineParityTraceTest) is not touched. This asserts nothing: it is
 * a generator, and the Python side owns the comparison.
 */
class FreestyleParityTraceTest {

    private class Frame(val traceId: String, val step: String, val tMs: Long, val builder: String,
                        val angle: String, val stable: Boolean, val keypoints: Array<Keypoint>)

    @Test
    fun `writes the reference freestyle trace for the python twin`() {
        val root = repositoryRoot()
        val sessions = listOf("recognition_plan.csv", "freestyle_plan.csv").flatMap { name ->
            val plan = File(root, "tests/parity/$name")
            check(plan.isFile) { "Missing plan at ${plan.absolutePath}" }
            planSessions(plan)
        }
        val trace = StringBuilder(TRACE_HEADER).append('\n')
        val sets = StringBuilder(SETS_HEADER).append('\n')
        sessions.forEach { (profile, frames) -> run(profile, frames, trace, sets) }
        File(root, "tests/parity/freestyle_trace_jvm.csv").writeText(trace.toString())
        File(root, "tests/parity/freestyle_sets_jvm.csv").writeText(sets.toString())
        println("Freestyle trace written (${sessions.sumOf { it.second.size }} frames)")

        val films = File(root, "tests/parity/films").listFiles { f -> f.extension == "csv" }
            ?.sortedBy { it.name }.orEmpty()
        if (films.isEmpty()) return
        val filmTrace = StringBuilder(TRACE_HEADER).append('\n')
        val filmSets = StringBuilder(SETS_HEADER).append('\n')
        films.forEach { run(CindyProfile.STANDARD, filmFrames(it), filmTrace, filmSets) }
        File(root, "tests/parity/freestyle_film_trace_jvm.csv").writeText(filmTrace.toString())
        File(root, "tests/parity/freestyle_film_sets_jvm.csv").writeText(filmSets.toString())
        println("Freestyle film trace written for ${films.size} film(s)")
    }

    private fun run(profile: CindyProfile, frames: List<Frame>, trace: StringBuilder, sets: StringBuilder) {
        val engine = FreestyleEngine(profile)
        engine.start(frames.first().tMs)
        val banked = Movement.entries.associateWithTo(mutableMapOf()) { 0 }
        frames.forEach { f ->
            val out = engine.onFrame(f.keypoints, f.tMs, f.stable)
            out.events.filterIsInstance<FreestyleEvent.Banked>().forEach { banked[it.movement] = banked.getValue(it.movement) + it.reps }
            val voice = out.voice.joinToString("|") {
                when (it) {
                    is FreestyleVoice.Confirmed -> "confirmed:${it.movement.id}:${it.count}"
                    is FreestyleVoice.Count -> "count:${it.count}"
                }
            }
            trace.append(csv(
                f.traceId, f.step, f.tMs.toString(), f.builder, f.angle, f.stable.toString(),
                // Guards the fixture geometry itself, as the recognition trace does.
                round(f.keypoints.sumOf { (it.x + it.y).toDouble() }),
                out.readout.figure.toString(), out.readout.movement?.id ?: "none",
                out.readout.movementTotal.toString(), out.readout.adjustable.toString(), out.readout.line,
                banked.getValue(Movement.PULL_UPS).toString(), banked.getValue(Movement.PUSH_UPS).toString(),
                banked.getValue(Movement.SQUATS).toString(), voice
            )).append('\n')
        }
        val id = frames.first().traceId
        val filed = engine.stop(frames.last().tMs)
        if (filed == null) {
            sets.append(csv(id, "filed", "0", "none", "0", "0", "0")).append('\n')
            return
        }
        sets.append(csv(id, "filed", "0", "none", filed.totalReps.toString(), filed.durationMs.toString(),
            filed.marks.size.toString())).append('\n')
        filed.sets.forEachIndexed { i, s ->
            sets.append(csv(id, "set", i.toString(), s.movement.name.lowercase(), s.reps.toString(),
                s.startMs.toString(), s.endMs.toString())).append('\n')
        }
        FreestyleSets.gapsBetween(filed.sets).forEachIndexed { i, g ->
            sets.append(csv(id, "gap", i.toString(), g.kind.name.lowercase(), "0",
                g.startMs.toString(), g.endMs.toString())).append('\n')
        }
    }

    private fun planSessions(plan: File): List<Pair<CindyProfile, List<Frame>>> =
        plan.readLines().drop(1).filter { it.isNotBlank() }.map { it.split(",") }
            .groupBy { it[TRACE_ID] }.map { (traceId, steps) ->
                val profile = CindyProfile(
                    pull = PullVariant.valueOf(steps.first()[PULL]),
                    push = PushVariant.valueOf(steps.first()[PUSH]),
                    squat = SquatVariant.valueOf(steps.first()[SQUAT])
                )
                profile to steps.map { step ->
                    val angle = step[ANGLE].toFloat()
                    val keypoints = when (step[BUILDER]) {
                        "pullup" -> PoseFixtures.pullup(angle)
                        "pushup" -> PoseFixtures.pushup(angle)
                        "kneepushup" -> PoseFixtures.kneePushup(angle)
                        "squat" -> PoseFixtures.squat(angle)
                        "empty" -> PoseFixtures.empty()
                        "onthefloor" -> PoseFixtures.onTheFloor()
                        "hangwithlegs" -> PoseFixtures.hangWithLegs(angle)
                        "kneelingup" -> PoseFixtures.kneelingUp(angle)
                        "headonplank" -> PoseFixtures.headOnPlank()
                        "leaningsquat" -> PoseFixtures.leaningSquat(angle)
                        "walking" -> PoseFixtures.walking(angle)
                        "squathandsbehindhead" -> PoseFixtures.squatHandsBehindHead(angle)
                        else -> error("Unknown builder in $traceId")
                    }
                    Frame(traceId, step[STEP], step[T_MS].toLong(), step[BUILDER], step[ANGLE],
                        step[STABLE] == "true", keypoints)
                }
            }

    /** A film's dumped keypoints: `tMs,stable,` then x,y,score for each of the 17 joints. */
    private fun filmFrames(file: File): List<Frame> {
        val id = file.nameWithoutExtension
        return file.readLines().drop(1).filter { it.isNotBlank() }.mapIndexed { i, line ->
            val cells = line.split(",")
            val keypoints = Array(17) { j ->
                Keypoint(cells[2 + 3 * j].toFloat(), cells[3 + 3 * j].toFloat(), cells[4 + 3 * j].toFloat())
            }
            Frame(id, i.toString(), cells[0].toLong(), "film", "0", cells[1] == "true", keypoints)
        }
    }

    private fun csv(vararg fields: String) =
        fields.joinToString(",") { "\"" + it.replace("\"", "\"\"") + "\"" }

    /** NaN has no stable cross-language spelling, so it is normalised here. */
    private fun round(value: Double): String =
        if (value.isNaN()) "nan" else String.format(Locale.US, "%.3f", value)

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
        const val PULL = 6
        const val PUSH = 7
        const val SQUAT = 8
        const val TRACE_HEADER = "traceId,step,tMs,builder,angle,stable,kpSum,figure,movement,movementTotal," +
            "adjustable,line,bankedPullUps,bankedPushUps,bankedSquats,voice"
        const val SETS_HEADER = "traceId,kind,index,what,reps,startMs,endMs"
    }
}
