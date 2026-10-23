package com.cindy.tracker

import android.graphics.Canvas
import android.graphics.Paint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
        val rects = mutableListOf<List<Float>>()

        override fun drawLine(startX: Float, startY: Float, stopX: Float, stopY: Float, paint: Paint) {
            lines += Line(startX, startY, stopX, stopY, paint.strokeWidth)
        }

        override fun drawCircle(cx: Float, cy: Float, radius: Float, paint: Paint) {
            circles += cx to cy
            radii += radius
        }

        override fun drawRect(left: Float, top: Float, right: Float, bottom: Float, paint: Paint) {
            rects += listOf(left, top, right, bottom)
        }
    }

    private val frameHeight = 640

    /** Every joint seen, laid out so each one has its own distinct x. */
    private fun seen() = Array(KP.COUNT) { Keypoint(10f + it, 20f + it, 0.9f) }

    private fun paint(
        keypoints: Array<Keypoint>,
        guide: WorkoutEngine.BarGuide? = null
    ): Recorder = Recorder().also { SkeletonPainter().paint(it, keypoints, frameHeight, guide) }

    @Test
    fun `a fully seen body gets every bone and every joint`() {
        val drawn = paint(seen())
        assertEquals(KP.SKELETON.size, drawn.lines.size)
        assertEquals(KP.COUNT, drawn.circles.size)
    }

    @Test
    fun `a joint under the threshold is skipped, and so is every bone touching it`() {
        val k = seen()
        k[KP.LEFT_ELBOW] = k[KP.LEFT_ELBOW].copy(score = PoseGeometry.MIN_SCORE - 0.01f)
        val drawn = paint(k)

        val touching = KP.SKELETON.count { (a, b) -> a == KP.LEFT_ELBOW || b == KP.LEFT_ELBOW }
        assertTrue("the elbow touches at least two bones", touching >= 2)
        assertEquals(KP.SKELETON.size - touching, drawn.lines.size)
        assertEquals(KP.COUNT - 1, drawn.circles.size)
        assertFalse(drawn.circles.contains(k[KP.LEFT_ELBOW].x to k[KP.LEFT_ELBOW].y))
    }

    @Test
    fun `a joint exactly at the threshold is drawn`() {
        val k = seen()
        k[KP.NOSE] = k[KP.NOSE].copy(score = PoseGeometry.MIN_SCORE)
        assertEquals(KP.COUNT, paint(k).circles.size)
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
    fun `a bar zone is drawn when given one, with its bar line and reset line`() {
        val guide = WorkoutEngine.BarGuide(
            zone = BarZone.Bounds(lineY = 100f, left = 50f, right = 300f, top = 40f, bottom = 180f),
            resetY = 160f,
            gateOpen = true
        )
        val drawn = paint(seen(), guide)

        assertTrue(drawn.rects.contains(listOf(50f, 40f, 300f, 180f)))
        // Two lines more than the bones: the bar itself, and where the head must come back to.
        assertEquals(KP.SKELETON.size + 2, drawn.lines.size)
        assertTrue(drawn.lines.any { it.y1 == 100f && it.y2 == 100f && it.x1 == 50f && it.x2 == 300f })
        assertTrue(drawn.lines.any { it.y1 == 160f && it.y2 == 160f && it.x1 == 50f && it.x2 == 300f })
    }
}
