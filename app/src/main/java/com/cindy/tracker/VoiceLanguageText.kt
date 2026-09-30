package com.cindy.tracker

/**
 * What the voice sheet's language list says, kept apart from the views that show it.
 *
 * Free of Android types on purpose: whether a row tells the athlete the truth about their phone
 * — that a voice is ready, or is on its way, or has been on its way suspiciously long — is the
 * whole point of the list, and is only worth checking if it can be checked without a screen.
 */
object VoiceLanguageText {

    /**
     * How long a download may go without its voice turning up before the row says so. The engine
     * reports no progress, so time is the only sign there is: one that is asked for on mobile
     * data it has been told to avoid can wait indefinitely, and looks exactly like one that is
     * merely slow.
     */
    const val STUCK_AFTER_MS = 2 * 60_000L

    /** How long to wait for the engine to answer at all before saying it isn't. */
    const val NO_ANSWER_AFTER_MS = 6_000L

    private const val NOT_ANSWERING = "This phone's voice engine isn't answering"
    private const val NOT_OFFERED = "Not offered by this phone's voice engine"

    /**
     * The second line of a language's row: where it stands on this phone.
     *
     * [state] is null until the engine has answered. [downloadingMs] is how long ago a download
     * was asked for, if one was, and [waitedMs] how long the list has been open.
     */
    fun caption(state: PackState?, downloadingMs: Long?, waitedMs: Long): String = when (state) {
        null -> if (waitedMs >= NO_ANSWER_AFTER_MS) NOT_ANSWERING else "Checking…"
        PackState.READY -> "Ready"
        PackState.DOWNLOADING ->
            if (stuck(downloadingMs)) {
                "Still waiting. The voice engine may need Wi-Fi. Tap to retry."
            } else {
                "Downloading…"
            }
        PackState.DOWNLOADABLE -> "Tap to download"
        PackState.ONLINE_ONLY -> "Online voice only. Counting stays in English."
        PackState.UNSUPPORTED -> NOT_OFFERED
    }

    private fun stuck(downloadingMs: Long?): Boolean = (downloadingMs ?: 0L) >= STUCK_AFTER_MS

    /**
     * Whether choosing the row should ask the engine for its voice.
     *
     * A language that is not on the phone, of course. And one whose request has gone unanswered
     * for [STUCK_AFTER_MS] too: the engine never says that a request was dropped, or cancelled in
     * its own screen, so asking again is the only way out of a row that would otherwise say
     * "downloading" until the sheet is closed. A request still fresh is left alone, since asking
     * again would only restart its clock.
     */
    fun asksForDownload(state: PackState?, downloadingMs: Long?): Boolean =
        state == PackState.DOWNLOADABLE || (state == PackState.DOWNLOADING && stuck(downloadingMs))

    /**
     * Whether the row can be chosen.
     *
     * A language nobody knows the state of yet can: refusing it because the engine is slow to
     * answer would make the list unusable for the first moment. One the engine does not speak
     * at all cannot, since choosing it would mean counting in English while the row says otherwise.
     */
    fun selectable(state: PackState?): Boolean = state != PackState.UNSUPPORTED

    /**
     * What to say when a preview starts, if it is not the voice a workout would use.
     *
     * A language that is not on the phone can only be previewed over the network, and the
     * athlete should know that is what they are hearing: it is a sample of the language, in a
     * voice they will not get until it has been downloaded. Nothing for a language the engine
     * does not speak, since nothing plays.
     */
    fun previewNote(state: PackState?): String? = when (state) {
        null, PackState.READY, PackState.UNSUPPORTED -> null
        else -> "Playing an online preview"
    }

    /** What to say when a preview does not play. */
    fun previewFailure(failure: SpeechFailure, pack: VoicePack): String = when (failure) {
        SpeechFailure.NETWORK -> "The ${pack.englishName} preview needs an internet connection"
        SpeechFailure.NOT_INSTALLED -> "The ${pack.englishName} voice is still downloading"
        SpeechFailure.UNAVAILABLE -> "This phone's voice engine can't play ${pack.englishName}"
        SpeechFailure.OTHER -> "The preview didn't play"
    }

    /**
     * What to say when the athlete asks the engine for something before it has answered at all:
     * that it is on its way, or, once it has had long enough, that it may not be.
     */
    fun engineSilent(waitedMs: Long): String =
        if (waitedMs >= NO_ANSWER_AFTER_MS) NOT_ANSWERING else "The voice engine is still starting. Try again in a moment."

    /** What a screen reader reads for a row: the language, how it stands, and whether it is the one. */
    fun description(pack: VoicePack, caption: String, chosen: Boolean): String =
        "${pack.nativeName}, ${pack.englishName}, $caption" + if (chosen) ", selected" else ""

    /**
     * What a screen reader reads for a row's preview button.
     *
     * The row's other half says when a language is not offered, and this half should not sound
     * like a button that works.
     */
    fun previewDescription(pack: VoicePack, state: PackState?): String =
        "Hear ${pack.englishName}" + if (state == PackState.UNSUPPORTED) ", ${NOT_OFFERED.lowercase()}" else ""

    /** Why a row that cannot be chosen says so when it is tapped. */
    fun unsupportedNotice(pack: VoicePack): String =
        "This phone's voice engine doesn't speak ${pack.englishName}. " +
            "Another engine in the phone's speech settings might."
}
