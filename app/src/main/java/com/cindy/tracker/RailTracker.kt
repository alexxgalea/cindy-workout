package com.cindy.tracker

import kotlin.math.abs

/** The bar as it is drawn: the line, and how far along it to draw. */
data class DrawnRail(val line: RailLine, val xFrom: Float, val xTo: Float)

/**
 * Learns where the pull-up bar is in the picture, while the athlete hangs from it, and keeps it.
 *
 * One look at one frame is not trusted: on the recorded wall bars five frames in six read the same
 * seven-degree tilt and one read twelve. So a hand votes, many frames' hands vote, and the bar is
 * only drawn once most of the votes agree on both the tilt and the height. After that it is *held*:
 * the bar does not move and neither does the phone, so it is not looked for again and cannot
 * flicker. It is dropped when the phone moves ([reset]) or when the gate has plainly moved to
 * another bar.
 *
 * Until it is sure there is no rail, and the caller draws the old gate. A bar drawn in the wrong
 * place with confidence is worse than the plain one.
 *
 * This only decides what is *drawn*. [BarZone] stays the gate; nothing here is read by the engine.
 * Called from the analysis thread; [reset] may come from any thread.
 */
class RailTracker(
    private val find: (Luma, Float, Float, Int, Int, Int) -> RailLine? = RailFinder::find
) {
    private companion object {
        /** Look once every this many calls: a look costs several milliseconds and the bar is still. */
        const val EVERY = 3
        const val MIN_VOTES = 6
        const val MAX_VOTES = 24

        /** Tilt votes within this of the middle one agree, in degrees. */
        const val TILT_AGREE = 2.5f
        /** Height votes within this of the middle one agree, in torsos. */
        const val HEIGHT_AGREE = 0.12f
        /** Share of the votes that must agree. */
        const val AGREEMENT = 0.7f

        /** A hand this close to the gate's bar, in torsos, can be holding it. */
        const val NEAR_BAR = 0.6f
        const val HALF_WIDTH_TORSOS = 0.7f
        const val ABOVE_TORSOS = 0.6f

        /** How far above a wrist the held bar can be: about a hand's length. */
        const val HAND_TORSOS = 0.2f

        /** How far the drawn bar reaches beyond the hands, in torsos. */
        const val REACH_TORSOS = 0.5f

        /** The gate is on another bar when it is this far, in torsos, from the held one. */
        const val ELSEWHERE = 1.0f
    }

    private class Vote(val tilt: Float, val yAtCentre: Float, val x: Float)

    private val votes = ArrayList<Vote>()
    private var calls = 0
    private var wanted = false

    @Volatile
    var rail: DrawnRail? = null
        private set

    /** Forgets the bar and every vote; the next hang learns it again. */
    @Synchronized
    fun reset() {
        votes.clear()
        rail = null
        calls = 0
    }

    /**
     * One analysed frame. [window] hands back the grey picture in the upright frame's pixels for a
     * window (x, y, width, height); it is only called when a look is actually taken.
     */
    @Synchronized
    fun observe(
        keypoints: Array<Keypoint>,
        guide: WorkoutEngine.BarGuide?,
        frameWidth: Int,
        frameHeight: Int,
        window: (Int, Int, Int, Int) -> Luma?
    ) {
        val torso = PoseGeometry.torsoLength(keypoints)
        if (guide == null || torso == null || torso <= 0f) return
        val centre = (guide.zone.left + guide.zone.right) / 2f

        rail?.let {
            if (abs(guide.zone.lineY - it.line.yAt(centre)) > ELSEWHERE * torso) reset()
            return
        }
        if (++calls % EVERY != 0) return

        val shoulders = listOf(KP.LEFT_SHOULDER, KP.RIGHT_SHOULDER)
            .map { keypoints[it] }.filter { PoseGeometry.ok(it) }
        if (shoulders.isEmpty()) return
        val shoulderY = shoulders.map { it.y }.average().toFloat()

        for (i in listOf(KP.LEFT_WRIST, KP.RIGHT_WRIST)) {
            val wrist = keypoints[i]
            // A hand that is hanging from the bar: seen, above the shoulders, at the gate's bar.
            if (!PoseGeometry.ok(wrist) || wrist.y >= shoulderY) continue
            if (abs(wrist.y - guide.zone.lineY) > NEAR_BAR * torso) continue
            if (wrist.x < guide.zone.left || wrist.x > guide.zone.right) continue

            val half = (HALF_WIDTH_TORSOS * torso).toInt()
            val above = (ABOVE_TORSOS * torso).toInt()
            val margin = half / 4 + 16
            val x0 = (wrist.x - half - margin).toInt().coerceAtLeast(0)
            val y0 = (wrist.y - above - margin).toInt().coerceAtLeast(0)
            val x1 = (wrist.x + half + margin).toInt().coerceAtMost(frameWidth - 1)
            val y1 = (wrist.y + margin).toInt().coerceAtMost(frameHeight - 1)
            val luma = window(x0, y0, x1 - x0 + 1, y1 - y0 + 1) ?: continue
            // The window's own pixels start at (x0, y0), so the hand is told in those.
            val line = find(luma, wrist.x - x0, wrist.y - y0, half, above, (HAND_TORSOS * torso).toInt()) ?: continue
            val atCentre = line.yAt(centre - x0) + y0
            votes += Vote(line.degrees, atCentre, wrist.x)
            if (votes.size > MAX_VOTES) votes.removeAt(0)
        }
        conclude(torso, centre)
    }

    private fun conclude(torso: Float, centre: Float) {
        if (votes.size < MIN_VOTES) return
        val tilt = votes.map { it.tilt }.sorted()[votes.size / 2]
        val height = votes.map { it.yAtCentre }.sorted()[votes.size / 2]
        val agreeing = votes.filter {
            abs(it.tilt - tilt) <= TILT_AGREE && abs(it.yAtCentre - height) <= HEIGHT_AGREE * torso
        }
        if (agreeing.size < AGREEMENT * votes.size) return
        val slope = RailLine(slope = Math.tan(Math.toRadians(tilt.toDouble())).toFloat(), xRef = centre, yRef = height)
        val xs = agreeing.map { it.x }
        rail = DrawnRail(
            line = slope,
            xFrom = xs.min() - REACH_TORSOS * torso,
            xTo = xs.max() + REACH_TORSOS * torso
        )
    }
}
