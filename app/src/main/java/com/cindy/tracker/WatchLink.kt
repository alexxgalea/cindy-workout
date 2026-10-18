package com.cindy.tracker

/** What the link to the paired heart-rate device is doing at this moment. */
enum class WatchLink {
    /** No device is paired, so there is no link to judge. */
    NOT_PAIRED,

    /** It is sending: a reading came in the last few seconds. */
    LIVE,

    /** It is not sending, whatever the reason: still connecting, broadcast off, Bluetooth off. */
    SILENT
}

/** What the athlete is asked, if anything, when they tap START. */
enum class WatchPrompt {
    NONE,

    /** No watch is paired: offer to pair one, since nothing else in the app does. */
    OFFER_TO_PAIR,

    /** A watch is paired but no heart rate is coming in: say so before a session starts without it. */
    ASK_ABOUT_SILENT_WATCH
}

/**
 * The rules for the heart-rate question at START, kept free of Android types so they can be
 * tested on their own: the screen that asks is not buildable on the JVM, and getting these
 * wrong is silent.
 */
object WatchLinks {

    /**
     * How recent a reading has to be for the watch to count as sending.
     *
     * A healthy watch sends about one a second, so five is a long gap. There is deliberately no
     * allowance for a link that is still being made: if no heart rate is arriving when START is
     * tapped, a session that starts now starts without one, and the athlete is told. Starting
     * anyway costs one tap.
     */
    const val SILENT_AFTER_MS = 5_000L

    /**
     * Judges the link from when it last spoke, on `SystemClock.elapsedRealtime`.
     *
     * Never having spoken is silent: a reading of 0 is a long time ago on any clock.
     */
    fun judge(paired: Boolean, lastReadingAt: Long, now: Long): WatchLink = when {
        !paired -> WatchLink.NOT_PAIRED
        now - lastReadingAt <= SILENT_AFTER_MS -> WatchLink.LIVE
        else -> WatchLink.SILENT
    }

    /**
     * What to ask when START is tapped.
     *
     * [bleAvailable] is whether the phone can talk to a watch at all: there is no point offering
     * one to a phone that cannot. [offerSilenced] is the athlete having said not to ask again.
     * A silent watch is always asked about, since that one cannot be turned off: it is a watch
     * the athlete chose, which is not doing what they chose it for.
     */
    fun promptAtStart(
        link: WatchLink,
        bleAvailable: Boolean,
        offerSilenced: Boolean
    ): WatchPrompt = when (link) {
        WatchLink.NOT_PAIRED ->
            if (bleAvailable && !offerSilenced) WatchPrompt.OFFER_TO_PAIR else WatchPrompt.NONE
        WatchLink.SILENT -> WatchPrompt.ASK_ABOUT_SILENT_WATCH
        WatchLink.LIVE -> WatchPrompt.NONE
    }

    /** The first line of the sheet that asks about a silent watch: what is wrong, if it is known. */
    fun why(status: HeartRateStatus): String = when (status) {
        HeartRateStatus.BLUETOOTH_OFF -> "Bluetooth is off on this phone."
        HeartRateStatus.NO_PERMISSION -> "Cindy is not allowed to use Bluetooth."
        else -> "It is paired but has sent no heart rate. Is heart-rate broadcast on?"
    }
}
