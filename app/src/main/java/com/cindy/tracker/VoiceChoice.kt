package com.cindy.tracker

import java.util.Locale

/**
 * One voice a text-to-speech engine offers, reduced to what choosing between voices needs.
 *
 * Free of Android types on purpose, like [Coach]: which voice the app ends up speaking with is the
 * decision that decides whether a Spanish workout is heard in Spanish, and it is only worth
 * making carefully if it can be tested against the shapes real engines return.
 */
data class EngineVoice(
    val name: String,
    /** ISO 639 language, lower case: `es`. */
    val language: String,
    /** ISO 3166 region, upper case, or empty: `ES`. */
    val country: String,
    /**
     * False for a voice the engine lists but has not fetched the data for yet. Such a voice
     * cannot speak until it has been downloaded, and asking it to fails with "not installed yet".
     */
    val installed: Boolean,
    /**
     * True for a voice that synthesises on the engine's servers. It needs a connection for every
     * utterance, so it is fine to preview and not something to count reps with.
     */
    val network: Boolean,
    /** `Voice.getQuality`: 100 (very low) to 500 (very high). */
    val quality: Int,
    /** `Voice.getLatency`: 100 (very low) to 500 (very high). Lower answers sooner. */
    val latency: Int
) {
    /** Whether this voice speaks [pack]'s language, in whichever region. */
    fun speaks(pack: VoicePack): Boolean = language == pack.tag || language == iso3(pack.tag)

    /** Whether a workout can be counted with this voice for [pack]: its data is here and it is local. */
    fun countsFor(pack: VoicePack): Boolean = speaks(pack) && installed && !network

    private fun iso3(tag: String): String =
        runCatching { Locale.forLanguageTag(tag).isO3Language }.getOrDefault("")
}

/** What an engine says when asked, without changing anything, whether it can speak a locale. */
enum class LanguageAvailability {
    /** Ready to speak. */
    AVAILABLE,
    /** Supported, but the voice data has to be fetched first. */
    MISSING_DATA,
    /** Not offered at all. */
    NOT_SUPPORTED
}

/** Where a language stands on this phone. */
enum class PackState {
    /** A voice for it is on the phone and can count a workout. */
    READY,
    /** Its voice data has been asked for and has not arrived. */
    DOWNLOADING,
    /** The engine offers it and the voice data can be fetched. */
    DOWNLOADABLE,
    /** Only a voice that runs on the engine's servers speaks it: previewable, not usable offline. */
    ONLINE_ONLY,
    /** The engine does not speak it. */
    UNSUPPORTED
}

/**
 * Deciding which of an engine's voices speaks a language, and where each language stands.
 *
 * The voice list is trusted over the availability codes. Engines disagree about the codes — some
 * answer "available" for a language they only speak over the network, some "missing data" for one
 * that is installed under another region — but a voice is a voice: installed or not, local or
 * not. The codes are the fallback for an engine that lists no voice for a language at all.
 */
object VoiceChoice {

    /**
     * Where [pack] stands, given every voice the engine listed.
     *
     * [availability] is what the engine answered to `isLanguageAvailable` for the pack's default
     * locale, or null when nobody asked. It is only consulted for a language the engine listed no
     * local voice for. [downloading] is the app's own knowledge that a download was asked for,
     * which the engine cannot report.
     */
    fun stateOf(
        pack: VoicePack,
        voices: List<EngineVoice>,
        availability: LanguageAvailability?,
        downloading: Boolean
    ): PackState {
        val mine = voices.filter { it.speaks(pack) }
        val local = mine.filter { !it.network }

        // A language nobody listed a voice for may still be spoken: the engine says so on request.
        if (local.any { it.installed } || (mine.isEmpty() && availability == LanguageAvailability.AVAILABLE)) {
            return PackState.READY
        }
        val downloadable = local.any { !it.installed } || availability == LanguageAvailability.MISSING_DATA
        return when {
            downloadable && downloading -> PackState.DOWNLOADING
            downloadable -> PackState.DOWNLOADABLE
            mine.any { it.network } -> PackState.ONLINE_ONLY
            else -> PackState.UNSUPPORTED
        }
    }

    /** The voice to count [pack]'s workout with, or null if the phone has none. Never a network one. */
    fun bestForWorkout(pack: VoicePack, voices: List<EngineVoice>, device: Locale): EngineVoice? =
        best(pack, device, voices.filter { it.countsFor(pack) })

    /** The voice to ask to fetch its data for [pack], or null if the engine lists none to fetch. */
    fun bestToDownload(pack: VoicePack, voices: List<EngineVoice>, device: Locale): EngineVoice? =
        best(pack, device, voices.filter { it.speaks(pack) && !it.installed && !it.network })

    /**
     * The voice to preview [pack] with: one that counts a workout if there is one, so a preview
     * is a true sample of what will be heard, and otherwise a network voice, so that a language
     * can be heard before it is downloaded.
     */
    fun bestForPreview(pack: VoicePack, voices: List<EngineVoice>, device: Locale): EngineVoice? =
        bestForWorkout(pack, voices, device)
            ?: best(pack, device, voices.filter { it.speaks(pack) && it.network })

    /**
     * The best of [candidates], by, in order: the region the phone itself is set to, if it is the
     * same language (so a phone in Mexico is answered in Mexican Spanish); the region the pack
     * prefers; the faster voice; the higher quality; and then the name, so the answer is stable.
     */
    private fun best(pack: VoicePack, device: Locale, candidates: List<EngineVoice>): EngineVoice? {
        val deviceRegion = if (device.language == pack.tag) device.country else ""
        return candidates.minWithOrNull(
            compareBy<EngineVoice>(
                { if (deviceRegion.isNotEmpty() && it.country.equals(deviceRegion, ignoreCase = true)) 0 else 1 },
                { if (it.country.equals(pack.defaultCountry, ignoreCase = true)) 0 else 1 },
                { it.latency },
                { -it.quality },
                { it.name }
            )
        )
    }
}
