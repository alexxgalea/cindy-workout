package com.cindy.tracker

import com.cindy.tracker.LockFixtures.moved
import com.cindy.tracker.LockFixtures.scaled
import com.cindy.tracker.LockFixtures.withScore
import java.io.File
import org.junit.Test

/**
 * Emits the reference trace that the Python port of [AthleteLock] is checked against.
 *
 * Replays tests/parity/lock_plan.csv through the production lock and writes every frame's
 * decision to tests/parity/lock_trace_jvm.csv; `lock_parity_check.py` replays the same plan
 * through the port and diffs the two row for row. Like [EngineParityTraceTest], it asserts
 * nothing itself.
 *
 * A pose is written `builder:angle:dx:dy:scale:blind`: a [PoseFixtures] body, scaled about the
 * origin, moved, then with the `|`-separated joints in `blind` made unseen. A control event, if
 * any, is applied before the frame at the same time.
 */
class LockParityTraceTest {

    @Test
    fun `writes the reference lock trace for the python port`() {
        val root = repositoryRoot()
        val plan = File(root, "tests/parity/lock_plan.csv")
        check(plan.isFile) { "Missing lock parity plan at ${plan.absolutePath}" }

        val rows = plan.readLines().drop(1).filter { it.isNotBlank() }.map { it.split(",") }
        val out = StringBuilder(HEADER).append('\n')

        rows.groupBy { it[TRACE_ID] }.forEach { (traceId, steps) ->
            val lock = AthleteLock()
            steps.forEach { step ->
                val now = step[T_MS].toLong()
                when (step[CONTROL]) {
                    "beginAcquiring" -> lock.beginAcquiring(now)
                    "confirm" -> lock.confirm(now)
                    "lose" -> lock.lose(now, clearStations = false)
                    "loseClear" -> lock.lose(now, clearStations = true)
                    "reset" -> lock.reset()
                    "" -> Unit
                    else -> error("Unknown control in $traceId")
                }
                val ctx = LockContext(
                    movement = movement(step[MOVEMENT]),
                    frameWidth = 480,
                    frameHeight = 640,
                    barZone = bar(step[BAR]),
                    calibrationReps = step[CALIB].toInt(),
                    workoutRunning = step[RUNNING] == "1"
                )
                val probes = if (step[PROBE].isEmpty()) emptyList() else listOf(pose(step[PROBE]))
                lock.onFrame(pose(step[PRIMARY]), probes, now, ctx)
                val wanted = lock.secondLookWanted
                var second = ""
                if (wanted && step[SECOND].isNotEmpty()) {
                    lock.reconsider(pose(step[SECOND]), now)
                    second = "${lock.verdict.name}/${lock.reason}"
                }
                out.append(
                    listOf(
                        traceId, step[STEP], step[T_MS], lock.state.name, lock.verdict.name, lock.reason,
                        lock.candidateChanged.toString(), lock.ambiguous.toString(),
                        lock.probeWanted.toString(), wanted.toString(),
                        lock.steer?.let { box(extent(it)) } ?: "",
                        lock.refusedBox?.let { box(it) } ?: "",
                        lock.knownOthers().joinToString(";") { box(it) },
                        lock.probeExclusions().joinToString(";") { box(it) },
                        second
                    ).joinToString(",")
                ).append('\n')
            }
        }

        val target = File(root, "tests/parity/lock_trace_jvm.csv")
        target.writeText(out.toString())
        println("Lock parity trace written to ${target.absolutePath} (${rows.size} frames)")
    }

    private fun pose(spec: String): Array<Keypoint> {
        val f = spec.split(":")
        val angle = f[1].toFloat()
        var k = when (f[0]) {
            "pullup" -> PoseFixtures.pullup(angle)
            "pushup" -> PoseFixtures.pushup(angle)
            "squat" -> PoseFixtures.squat(angle)
            else -> error("Unknown builder $spec")
        }
        val scale = f[4].toFloat()
        if (scale != 1f) k = k.scaled(scale)
        k = k.moved(f[2].toFloat(), f[3].toFloat())
        if (f[5].isNotEmpty()) k = k.withScore(0f, *f[5].split("|").map { it.toInt() }.toIntArray())
        return k
    }

    private fun movement(name: String) = when (name) {
        "pullup" -> Exercise.PULLUP
        "pushup" -> Exercise.PUSHUP
        "squat" -> Exercise.SQUAT
        else -> error("Unknown movement $name")
    }

    private fun bar(spec: String): BarZone.Bounds? {
        if (spec.isEmpty()) return null
        val v = spec.split("|").map { it.toFloat() }
        return BarZone.Bounds(lineY = v[1], left = v[0], right = v[2], top = v[1], bottom = v[3])
    }

    /** The confident joints' extent of a pose, which is how a steer is written. */
    private fun extent(k: Array<Keypoint>): PoseBox {
        val seen = k.filter { it.score >= PoseGeometry.MIN_SCORE }
        return PoseBox(seen.minOf { it.x }, seen.minOf { it.y }, seen.maxOf { it.x }, seen.maxOf { it.y })
    }

    private fun box(b: PoseBox) = listOf(b.left, b.top, b.right, b.bottom)
        .joinToString("|") { String.format(java.util.Locale.US, "%.3f", it.toDouble()) }

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
        const val MOVEMENT = 3
        const val CONTROL = 4
        const val PRIMARY = 5
        const val PROBE = 6
        const val SECOND = 7
        const val CALIB = 8
        const val RUNNING = 9
        const val BAR = 10
        const val HEADER = "traceId,step,tMs,state,verdict,reason,candidateChanged,ambiguous," +
            "probeWanted,secondLookWanted,steer,refusedBox,knownOthers,probeExclusions,second"
    }
}
