package com.cindy.tracker

import java.io.BufferedWriter
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/**
 * Writes, for every frame the engine is given, what it was given and what it decided, so a session
 * that miscounted on the phone can be replayed exactly by the desktop harness
 * (`tools/video_regression/replay_trace.py`).
 *
 * A film cannot stand in for this. It shows the picture, not the frames the analyser dropped, the
 * clock the engine was handed, or the keypoints of a frame the film interpolated over.
 *
 * Debug builds only, and only ever touched from the analysis thread, so it takes no lock. One file
 * per session, opened at the first SETUP or RUNNING frame and closed at the first frame after.
 */
class EngineTrace(private val dir: File) {

    private var out: BufferedWriter? = null
    private var rows = 0

    /** The file being written, or null between sessions. */
    var file: File? = null
        private set

    /** Analysis calls refused since the last row because the previous frame was still running. */
    val refused = AtomicInteger()

    fun frame(row: Row) {
        val w = out ?: open()
        val skipped = refused.getAndSet(0)
        w.write(row.csv(skipped))
        w.newLine()
        // A session that ends in a crash should still leave most of itself behind.
        if (++rows % FLUSH_EVERY == 0) w.flush()
    }

    /** Ends the session's file; harmless when none is open. */
    fun close() {
        out?.run { flush(); close() }
        out = null
        rows = 0
    }

    private fun open(): BufferedWriter {
        dir.mkdirs()
        val f = File(dir, "engine-${System.currentTimeMillis()}.csv")
        file = f
        return f.bufferedWriter().also {
            it.write(HEADER)
            it.newLine()
            out = it
        }
    }

    /** One analysed frame. [setupStage] is set on a SETUP frame, [event] on a RUNNING one. */
    class Row(
        val captureNanos: Long,
        val engineMs: Long,
        val convertMs: Long,
        val prepMs: Long,
        val inferMs: Long,
        val captureAgeMs: Long?,
        val tracking: Boolean,
        val softGain: Float,
        val thermal: Int,
        val frameW: Int,
        val frameH: Int,
        val keypoints: Array<Keypoint>,
        val setupStage: String?,
        val exercise: Exercise,
        val reps: Int,
        val event: RepEvent?,
        val phase: String,
        val signal: Float,
        val rejection: String?,
        val profile: CindyProfile,
        val smartSquats: Boolean
    ) {
        fun csv(skipped: Int): String = buildString {
            append(if (setupStage != null) "setup" else "run").append(',')
            append(captureNanos).append(',').append(engineMs).append(',')
            append(convertMs).append(',').append(prepMs).append(',').append(inferMs).append(',')
            append(captureAgeMs ?: "").append(',').append(skipped).append(',')
            append(if (tracking) 1 else 0).append(',').append(f(softGain)).append(',')
            append(thermal).append(',').append(frameW).append(',').append(frameH).append(',')
            append(setupStage ?: "").append(',').append(exercise.name).append(',')
            append(reps).append(',').append(event?.name ?: "").append(',')
            append(phase).append(',').append(f(signal)).append(',')
            // The engine's reasons are prose; keep the comma out of the CSV.
            append(rejection?.replace(',', ';') ?: "").append(',')
            append(profile.pull.name).append(',').append(profile.push.name).append(',')
            append(profile.squat.name).append(',').append(if (smartSquats) 1 else 0)
            for (k in keypoints) {
                append(',').append(f(k.x)).append(',').append(f(k.y)).append(',').append(f(k.score))
            }
        }
    }

    companion object {
        private const val FLUSH_EVERY = 30

        // A Float's shortest round-trip spelling, so the replay lands on the same side of every
        // exact threshold the engine compares against.
        private fun f(v: Float) = v.toString()

        val HEADER = buildString {
            append("kind,capture_ns,engine_ms,convert_ms,prep_ms,infer_ms,capture_age_ms,")
            append("refused_before,tracking,soft_gain,thermal,frame_w,frame_h,setup_stage,")
            append("exercise,reps,event,phase,signal,rejection,pull,push,squat,smart_squats")
            for (i in 0 until 17) append(",k${i}_x,k${i}_y,k${i}_s")
        }
    }
}
