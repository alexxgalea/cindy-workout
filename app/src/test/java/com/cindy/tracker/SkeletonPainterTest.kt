package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Paint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import kotlin.math.hypot
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the painter chooses to draw, read off a canvas that records its calls rather than its
 * pixels: which bones, which joints, and whether a bar zone is there at all.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SkeletonPainterTest {

    private class Recorder : Canvas() {
        class Line(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val width: Float)

        val lines = mutableListOf<Line>()
        val circles = mutableListOf<Pair<Float, Float>>()
        val radii = mutableListOf<Float>()
        val circleStyles = mutableListOf<Paint.Style>()
        val circleStrokes = mutableListOf<Float>()
        val rects = mutableListOf<List<Float>>()

        override fun drawLine(startX: Float, startY: Float, stopX: Float, stopY: Float, paint: Paint) {
            lines += Line(startX, startY, stopX, stopY, paint.strokeWidth)
        }

        override fun drawCircle(cx: Float, cy: Float, radius: Float, paint: Paint) {
            circles += cx to cy
            radii += radius
            circleStyles += paint.style
            circleStrokes += paint.strokeWidth
        }

        override fun drawRect(left: Float, top: Float, right: Float, bottom: Float, paint: Paint) {
            rects += listOf(left, top, right, bottom)
        }
    }

    private val frameHeight = 640

    /** Every joint seen, laid out so each one has its own distinct x. */
    private fun seen() = Array(KP.COUNT) { Keypoint(10f + it, 20f + it, 0.9f) }

    /** Every joint seen, far enough apart that no bone is short enough to be trimmed by half. */
    private fun spread() = Array(KP.COUNT) { Keypoint(100f + it * 30f, 50f + it * 20f, 0.9f) }

    /** The joints that are drawn: everything below the face. */
    private val bodyJoints = KP.COUNT - KP.LEFT_SHOULDER

    private fun paint(
        keypoints: Array<Keypoint>,
        guide: WorkoutEngine.BarGuide? = null
    ): Recorder = Recorder().also { SkeletonPainter().paint(it, keypoints, frameHeight, guide) }

    @Test
    fun `a fully seen body gets every bone and a ring on every joint below the face`() {
        val drawn = paint(seen())
        assertEquals(KP.SKELETON.size, drawn.lines.size)
        assertEquals(bodyJoints, drawn.circles.size)
    }

    @Test
    fun `the face gets no joints, however well it is seen`() {
        val k = seen()
        for (i in KP.NOSE until KP.LEFT_SHOULDER) k[i] = k[i].copy(score = 0.99f)
        val drawn = paint(k)
        for (i in KP.NOSE until KP.LEFT_SHOULDER) {
            assertFalse("face point $i was drawn", drawn.circles.contains(k[i].x to k[i].y))
        }
    }

    @Test
    fun `joints are rings, not discs`() {
        val drawn = paint(seen())
        assertTrue(drawn.circleStyles.all { it == Paint.Style.STROKE })
        assertTrue(drawn.circleStrokes.all { it > 0f })
    }

    @Test
    fun `a bone stops short of its joints by more than the ring needs`() {
        val k = spread()
        val drawn = paint(k)
        val ring = drawn.radii[0] + drawn.circleStrokes[0] / 2f
        KP.SKELETON.forEachIndexed { i, (a, b) ->
            val line = drawn.lines[i]
            val fromA = hypot(line.x1 - k[a].x, line.y1 - k[a].y)
            val fromB = hypot(line.x2 - k[b].x, line.y2 - k[b].y)
            assertTrue("bone $a-$b touches joint $a", fromA > ring)
            assertTrue("bone $a-$b touches joint $b", fromB > ring)
        }
    }

    @Test
    fun `a very short bone is trimmed in proportion and never turned inside out`() {
        val k = spread()
        // Pull the left elbow to 5 px from the shoulder: a body seen from far away.
        val s = k[KP.LEFT_SHOULDER]
        k[KP.LEFT_ELBOW] = Keypoint(s.x + 3f, s.y + 4f, 0.9f)
        val drawn = paint(k)
        val i = KP.SKELETON.indexOfFirst { it == (KP.LEFT_SHOULDER to KP.LEFT_ELBOW) }
        val line = drawn.lines[i]
        val before = hypot(k[KP.LEFT_ELBOW].x - s.x, k[KP.LEFT_ELBOW].y - s.y)
        val after = hypot(line.x2 - line.x1, line.y2 - line.y1)
        assertTrue("the bone still shows", after > 0f)
        assertTrue("the bone did not grow", after < before)
        // Same direction as the bone: start nearer the shoulder than the end is.
        assertTrue(hypot(line.x1 - s.x, line.y1 - s.y) < hypot(line.x2 - s.x, line.y2 - s.y))
    }

    @Test
    fun `a joint under the threshold is skipped, and so is every bone touching it`() {
        val k = seen()
        k[KP.LEFT_ELBOW] = k[KP.LEFT_ELBOW].copy(score = PoseGeometry.MIN_SCORE - 0.01f)
        val drawn = paint(k)

        val touching = KP.SKELETON.count { (a, b) -> a == KP.LEFT_ELBOW || b == KP.LEFT_ELBOW }
        assertTrue("the elbow touches at least two bones", touching >= 2)
        assertEquals(KP.SKELETON.size - touching, drawn.lines.size)
        assertEquals(bodyJoints - 1, drawn.circles.size)
        assertFalse(drawn.circles.contains(k[KP.LEFT_ELBOW].x to k[KP.LEFT_ELBOW].y))
    }

    @Test
    fun `a joint exactly at the threshold is drawn`() {
        val k = seen()
        k[KP.LEFT_WRIST] = k[KP.LEFT_WRIST].copy(score = PoseGeometry.MIN_SCORE)
        assertEquals(bodyJoints, paint(k).circles.size)
    }

    @Test
    fun `an unseen body draws nothing`() {
        val k = Array(KP.COUNT) { Keypoint(1f, 1f, 0f) }
        val drawn = paint(k)
        assertTrue(drawn.lines.isEmpty())
        assertTrue(drawn.circles.isEmpty())
    }

    @Test
    fun `weights are a fraction of the frame height`() {
        val small = Recorder().also { SkeletonPainter().paint(it, seen(), 640, null) }
        val large = Recorder().also { SkeletonPainter().paint(it, seen(), 1280, null) }
        assertEquals(small.lines[0].width * 2, large.lines[0].width, 1e-4f)
        assertEquals(small.radii[0] * 2, large.radii[0], 1e-4f)
    }

    @Test
    fun `no bar zone is drawn unless one is given`() {
        assertTrue(paint(seen(), guide = null).rects.isEmpty())
    }

    @Test
    fun `the old gate's box and level line are never drawn, whatever the gate says`() {
        val guide = WorkoutEngine.BarGuide(
            zone = BarZone.Bounds(lineY = 100f, left = 50f, right = 300f, top = 40f, bottom = 180f),
            resetY = 160f,
            gateOpen = true
        )
        val drawn = paint(seen(), guide)

        assertTrue(drawn.rects.isEmpty())
        assertEquals(KP.SKELETON.size, drawn.lines.size)
    }

    @Test
    fun `a bar the picture has shown is drawn tilted along itself, thin, with no box`() {
        val rail = DrawnRail(
            line = RailLine(slope = 0.13f, xRef = 150f, yRef = 100f),
            xFrom = 80f,
            xTo = 260f
        )
        val guide = WorkoutEngine.BarGuide(
            zone = BarZone.Bounds(lineY = 130f, left = 50f, right = 300f, top = 40f, bottom = 180f),
            resetY = 200f,
            gateOpen = true,
            rail = rail
        )
        val drawn = paint(seen(), guide)

        assertTrue(drawn.rects.isEmpty())
        // The bar and the head's return line, besides the bones.
        assertEquals(KP.SKELETON.size + 2, drawn.lines.size)
        val bar = drawn.lines.first { it.x1 == 80f && it.x2 == 260f && it.y1 != it.y2 }
        assertEquals(100f + 0.13f * (80f - 150f), bar.y1, 1e-3f)
        assertEquals(0.13f, (bar.y2 - bar.y1) / (bar.x2 - bar.x1), 1e-3f)
        // Thinner than a bone, so the real tube is still seen under it.
        assertTrue(bar.width < drawn.lines.last().width)
    }
}
