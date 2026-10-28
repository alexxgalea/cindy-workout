package com.cindy.tracker

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ten push-ups on a hot phone, and the three the counter used to miss among them.
 *
 * tests/traces/push_ups_hot_phone.csv is the push-up part of a real session, written by a debug
 * build on a Huawei P40 that had been running hot: about eight analysed frames a second, so a
 * quick push-up's bottom landed on one or two of them. Each row is the keypoints and the clock the
 * engine was given, from the moment the athlete skipped the pull-ups. Every push-up went to an
 * elbow of 49 to 64 degrees on video, and the session ended the set only at the thirteenth.
 */
class HotPhonePushUpsTest {

    /** When each push-up bottomed out, in the trace's clock, read off the screen recording. */
    private val bottoms = listOf(5208L, 6228L, 7158L, 8068L, 8948L, 9878L, 10818L, 11698L, 12688L,
        13698L, 14758L)

    @Test
    fun `ten push-ups a hot phone saw finish the set`() {
        // The app's way in: setup skipped, then the pull-ups.
        val engine = WorkoutEngine()
        engine.beginSetup()
        engine.finishSetup()
        engine.skipExercise()
        assertEquals(Exercise.PUSHUP, engine.exercise)

        val counted = mutableListOf<Long>()
        var doneAt = -1L
        trace().forEach { (now, tracking, keypoints) ->
            val event = engine.onFrame(keypoints, now, tracking)
            if (event != RepEvent.NONE && doneAt < 0) counted += now
            if (event == RepEvent.EXERCISE_DONE && doneAt < 0) doneAt = now
        }
        assertEquals(10, counted.size)
        // Each push-up is booked on its own way up: after its bottom and before the next one.
        counted.forEachIndexed { i, at ->
            assertTrue("push-up ${i + 1} booked at $at", at > bottoms[i] && at < bottoms[i + 1])
        }
        assertTrue("set finished at $doneAt", doneAt in bottoms[9]..bottoms[10])
    }

    private fun trace(): List<Triple<Long, Boolean, Array<Keypoint>>> {
        val file = File(repositoryRoot(), "tests/traces/push_ups_hot_phone.csv")
        return file.readLines().drop(1).filter { it.isNotBlank() }.map { line ->
            val f = line.split(',')
            val keypoints = Array(17) { i ->
                Keypoint(f[2 + 3 * i].toFloat(), f[3 + 3 * i].toFloat(), f[4 + 3 * i].toFloat())
            }
            Triple(f[0].toLong(), f[1] == "1", keypoints)
        }
    }

    private fun repositoryRoot(): File {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        return dir ?: error("Could not locate the repository root")
    }
}
