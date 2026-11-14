package com.cindy.tracker

/**
 * What the device video regression test may claim, kept free of Android so the JVM can test it.
 *
 * The desktop batch applies a scenario's `light` model and checks its `expectedTracking`; the
 * device test applies neither. A clip that needs either would be fed clean frames and judged
 * against a label written for dim ones, so it is left out and named, never counted as a pass.
 */
object DeviceRunPlan {

    /**
     * Frames per second of a clip. A phone recording carries a capture rate; a downloaded clip
     * usually does not, so the rate falls back to the frame count over the duration. Null when
     * neither gives a positive figure.
     */
    fun framesPerSecond(captureRate: String?, frameCount: Int, durationMs: String?): Float? {
        captureRate?.toFloatOrNull()?.takeIf { it > 0f }?.let { return it }
        val duration = durationMs?.toLongOrNull()?.takeIf { it > 0L } ?: return null
        return (frameCount * 1000f / duration).takeIf { it > 0f }
    }

    /** The line to log and report when a scenario cannot be run honestly here, else null. */
    fun notRunReason(id: String, hasLight: Boolean, expectedTracking: String?): String? {
        if (!hasLight && expectedTracking.isNullOrBlank()) return null
        return "NOT RUN on device: low-light model and expected tracking are only applied by the desktop batch: $id"
    }

    /** The message that goes in the test's result, so the left-out clips are never a quiet pass. */
    fun notRunSummary(reasons: List<String>): String =
        "${reasons.size} scenario(s) NOT RUN on device, not counted as passes:\n" + reasons.joinToString("\n")
}
