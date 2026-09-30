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

    /**
     * The second line of a language's row: where it stands on this phone.
     *
     * [state] is null until the engine has answered. [downloadingMs] is how long ago a download
     * was asked for, if one was, and [waitedMs] how long the list has been open.
     */
    fun caption(state: PackState?, downloadingMs: Long?, waitedMs: Long): String = when (state) {
        null ->
            if (waitedMs >= NO_ANSWER_AFTER_MS) "This phone's voice engine isn't answering" else "Checking…"
        PackState.READY -> "Ready"
        PackState.DOWNLOADING ->
            if ((downloadingMs ?: 0L) >= STUCK_AFTER_MS) {
                "Still waiting. The voice engine may need Wi-Fi."
            } else {
                "Downloading…"
            }
        PackState.DOWNLOADABLE -> "Tap to download"
        PackState.ONLINE_ONLY -> "Online voice only. Counting stays in English."
        PackState.UNSUPPORTED -> "Not offered by this phone's voice engine"
    }

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
     * voice they will not get until it has been downloaded.
     */
    fun previewNote(state: PackState?): String? =
        if (state == null || state == PackState.READY) null else "Playing an online preview"

    /** What to say when a preview does not play. */
    fun previewFailure(failure: SpeechFailure, pack: VoicePack): String = when (failure) {
        SpeechFailure.NETWORK -> "The ${pack.englishName} preview needs an internet connection"
        SpeechFailure.NOT_INSTALLED -> "The ${pack.englishName} voice is still downloading"
        SpeechFailure.UNAVAILABLE -> "This phone's voice engine can't play ${pack.englishName}"
        SpeechFailure.OTHER -> "The preview didn't play"
    }

    /** What a screen reader reads for a row: the language, how it stands, and whether it is the one. */
    fun description(pack: VoicePack, caption: String, chosen: Boolean): String =
        "${pack.nativeName}, ${pack.englishName}, $caption" + if (chosen) ", selected" else ""

    /** What a screen reader reads for a row's preview button. */
    fun previewDescription(pack: VoicePack): String = "Hear ${pack.englishName}"

    /** Why a row that cannot be chosen says so when it is tapped. */
    fun unsupportedNotice(pack: VoicePack): String =
        "This phone's voice engine doesn't speak ${pack.englishName}. " +
            "Another engine in the phone's speech settings might."
}
