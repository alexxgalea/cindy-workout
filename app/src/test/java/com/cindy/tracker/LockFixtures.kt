package com.cindy.tracker

/**
 * Moves, scales and blinds the synthetic bodies in [PoseFixtures], so the identity lock can be
 * shown a second person, the same person further away, or a partly seen torso.
 *
 * Unseen keypoints are left where they are: they carry no position.
 */
object LockFixtures {

    fun Array<Keypoint>.moved(dx: Float, dy: Float): Array<Keypoint> =
        map { if (it.score > 0f) Keypoint(it.x + dx, it.y + dy, it.score) else it }.toTypedArray()

    /** Scales about the origin, which every fixture is built around. */
    fun Array<Keypoint>.scaled(factor: Float): Array<Keypoint> =
        map { if (it.score > 0f) Keypoint(it.x * factor, it.y * factor, it.score) else it }.toTypedArray()

    fun Array<Keypoint>.withScore(score: Float, vararg joints: Int): Array<Keypoint> {
        val out = copyOf()
        for (j in joints) out[j] = Keypoint(out[j].x, out[j].y, score)
        return out
    }

    /** A joint moved on its own, as when MoveNet puts one wrist or hip on someone else. */
    fun Array<Keypoint>.jointMoved(joint: Int, dx: Float, dy: Float): Array<Keypoint> {
        val out = copyOf()
        out[joint] = Keypoint(out[joint].x + dx, out[joint].y + dy, out[joint].score)
        return out
    }

    /** Someone standing still: the top of a squat. */
    fun standing(): Array<Keypoint> = PoseFixtures.squat(175f)

    /** Someone hanging from the bar, in the pull-up start position. */
    fun hanging(): Array<Keypoint> = PoseFixtures.pullup(170f)
}
