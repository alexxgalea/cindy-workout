package com.cindy.tracker

/**
 * The start position of each movement, as poses rather than as a sentence.
 *
 * The athlete is told "Hang from the bar" or "Get set on the floor" already; what the words
 * cannot carry is what that looks like, which is exactly the thing someone unsure of the app
 * needs. So each movement gets a short loop that walks into its own starting position and holds
 * there.
 *
 * ### Why this and not a video
 *
 * These are joints, not frames: thirteen of them, the same thirteen [OverlayView] already draws
 * from MoveNet, three keyframes per movement. The whole table below is about two kilobytes, it
 * takes the theme's colours like anything else drawn with a [android.graphics.Paint], and it is
 * rendered by code that already exists — so the demonstrator and the athlete's own skeleton are
 * drawn in one visual language and "match this" needs no caption.
 *
 * A GIF could do none of that: 256 colours with no usable alpha dithers visibly on a dark glass
 * panel, and it could never be recoloured. A rigged glTF model and a renderer to play it would
 * add five to fifteen megabytes to an APK that drops the x86 ABIs to save nine, for a hint that
 * is on screen for two seconds.
 *
 * Coordinates are in each movement's own box, y down, and carry a **z** so the figure can be
 * turned: [StartPoseView] rotates about the vertical axis and projects, which is what gives it
 * depth without a mesh. Left-hand joints sit at negative z, right-hand at positive.
 *
 * If motion capture is ever wanted, this table is the format to fill: run a clip through the
 * Python harness in `tools/video_regression` and keep the keypoints it emits.
 */
object StartPoses {

    /** Indices into a pose's flat `x, y, z` triples. */
    const val NOSE = 0
    const val L_SHOULDER = 1
    const val R_SHOULDER = 2
    const val L_ELBOW = 3
    const val R_ELBOW = 4
    const val L_WRIST = 5
    const val R_WRIST = 6
    const val L_HIP = 7
    const val R_HIP = 8
    const val L_KNEE = 9
    const val R_KNEE = 10
    const val L_ANKLE = 11
    const val R_ANKLE = 12

    const val JOINTS = 13

    /** Pairs of joint indices to stroke, in back-to-front order within each side. */
    val BONES: Array<IntArray> = arrayOf(
        intArrayOf(L_SHOULDER, L_ELBOW), intArrayOf(L_ELBOW, L_WRIST),
        intArrayOf(R_SHOULDER, R_ELBOW), intArrayOf(R_ELBOW, R_WRIST),
        intArrayOf(L_SHOULDER, R_SHOULDER), intArrayOf(L_HIP, R_HIP),
        intArrayOf(L_SHOULDER, L_HIP), intArrayOf(R_SHOULDER, R_HIP),
        intArrayOf(L_HIP, L_KNEE), intArrayOf(L_KNEE, L_ANKLE),
        intArrayOf(R_HIP, R_KNEE), intArrayOf(R_KNEE, R_ANKLE)
    )

    /**
     * One movement's loop.
     *
     * [frames] runs approach, approach, and then the position itself, which is the one held.
     * [barY] is drawn only where there is a bar to hang from.
     */
    class Loop(
        val boxWidth: Float,
        val boxHeight: Float,
        val groundY: Float,
        val barY: Float?,
        val headRadius: Float,
        val frames: Array<FloatArray>
    )

    fun of(exercise: Exercise): Loop = when (exercise) {
        Exercise.PULLUP -> PULL_UP
        Exercise.PUSHUP -> PUSH_UP
        Exercise.SQUAT -> SQUAT
    }

    val PULL_UP = Loop(
        boxWidth = 180f, boxHeight = 210f, groundY = 202f, barY = 20f, headRadius = 11f,
        frames = arrayOf(
            floatArrayOf(
                90f, 86f, 2f,
                81f, 104f, -8f,
                99f, 104f, 8f,
                78f, 74f, -8f,
                102f, 74f, 8f,
                81f, 44f, -8f,
                99f, 44f, 8f,
                84f, 142f, -8f,
                96f, 142f, 8f,
                83f, 172f, -8f,
                97f, 172f, 8f,
                82f, 202f, -8f,
                98f, 202f, 8f
            ),
            floatArrayOf(
                90f, 80f, 2f,
                81f, 92f, -8f,
                99f, 92f, 8f,
                78f, 54f, -8f,
                102f, 54f, 8f,
                80f, 20f, -8f,
                100f, 20f, 8f,
                84f, 134f, -8f,
                96f, 134f, 8f,
                83f, 168f, -8f,
                97f, 168f, 8f,
                82f, 202f, -8f,
                98f, 202f, 8f
            ),
            floatArrayOf(
                90f, 74f, 2f,
                81f, 86f, -8f,
                99f, 86f, 8f,
                78f, 52f, -8f,
                102f, 52f, 8f,
                80f, 20f, -8f,
                100f, 20f, 8f,
                84f, 130f, -8f,
                96f, 130f, 8f,
                83f, 164f, -8f,
                97f, 164f, 8f,
                86f, 188f, -8f,
                94f, 188f, 8f
            )
        )
    )

    val PUSH_UP = Loop(
        boxWidth = 210f, boxHeight = 150f, groundY = 132f, barY = null, headRadius = 10f,
        frames = arrayOf(
            floatArrayOf(
                44f, 72f, 2f,
                60f, 82f, -7f,
                58f, 84f, 7f,
                58f, 106f, -7f,
                56f, 108f, 7f,
                56f, 132f, -7f,
                54f, 132f, 7f,
                110f, 88f, -7f,
                108f, 90f, 7f,
                140f, 132f, -7f,
                138f, 132f, 7f,
                164f, 120f, -7f,
                162f, 122f, 7f
            ),
            floatArrayOf(
                44f, 78f, 2f,
                60f, 88f, -7f,
                58f, 90f, 7f,
                58f, 110f, -7f,
                56f, 112f, 7f,
                56f, 132f, -7f,
                54f, 132f, 7f,
                108f, 96f, -7f,
                106f, 98f, 7f,
                138f, 118f, -7f,
                136f, 120f, 7f,
                164f, 132f, -7f,
                162f, 132f, 7f
            ),
            floatArrayOf(
                42f, 84f, 2f,
                58f, 94f, -7f,
                56f, 96f, 7f,
                56f, 113f, -7f,
                54f, 115f, 7f,
                54f, 132f, -7f,
                52f, 132f, 7f,
                106f, 104f, -7f,
                104f, 106f, 7f,
                136f, 118f, -7f,
                134f, 120f, 7f,
                164f, 132f, -7f,
                162f, 132f, 7f
            )
        )
    )

    val SQUAT = Loop(
        boxWidth = 180f, boxHeight = 190f, groundY = 170f, barY = null, headRadius = 11f,
        frames = arrayOf(
            floatArrayOf(
                90f, 60f, 2f,
                80f, 80f, -8f,
                100f, 81f, 8f,
                70f, 98f, -8f,
                110f, 98f, 8f,
                72f, 114f, -8f,
                108f, 114f, 8f,
                84f, 120f, -8f,
                96f, 120f, 8f,
                77f, 144f, -8f,
                103f, 144f, 8f,
                81f, 170f, -8f,
                99f, 170f, 8f
            ),
            floatArrayOf(
                90f, 47f, 2f,
                80f, 67f, -8f,
                100f, 68f, 8f,
                72f, 89f, -8f,
                108f, 89f, 8f,
                72f, 109f, -8f,
                108f, 109f, 8f,
                83f, 110f, -8f,
                97f, 110f, 8f,
                79f, 139f, -8f,
                101f, 139f, 8f,
                81f, 170f, -8f,
                99f, 170f, 8f
            ),
            floatArrayOf(
                90f, 34f, 2f,
                80f, 54f, -8f,
                100f, 55f, 8f,
                75f, 80f, -8f,
                105f, 80f, 8f,
                73f, 104f, -8f,
                107f, 104f, 8f,
                83f, 100f, -8f,
                97f, 100f, 8f,
                82f, 135f, -8f,
                98f, 135f, 8f,
                81f, 170f, -8f,
                99f, 170f, 8f
            )
        )
    )
}
