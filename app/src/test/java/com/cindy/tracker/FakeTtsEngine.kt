package com.cindy.tracker

import java.util.Locale

/**
 * A text-to-speech engine that does what tests tell it to and remembers what it was asked.
 *
 * It behaves like the real ones in the ways that matter here: asking for a language it can
 * speak picks that language's default voice; asking for one it cannot changes nothing; asking
 * for a voice by name sets it unless it is on the refused list; and every call is written down,
 * in order, so a test can say not only what ended up set but how the engine was walked there.
 */
class FakeTtsEngine : TtsEngine {

    override var listener: EngineListener? = null

    /** What [voices] returns. */
    var listed: List<EngineVoice> = emptyList()

    /** What the engine answers when asked about a locale, by language tag. Anything else is not supported. */
    val answers = mutableMapOf<String, LanguageAvailability>()

    /** The voice the engine picks as the default for a locale, by language tag. */
    val defaults = mutableMapOf<String, String>()

    /** Voices that [setVoice] declines. */
    val refused = mutableSetOf<String>()

    /** The voice the engine is set to now. */
    var current: String? = null

    /** Every call that changes something, in order: `setLanguage:es-ES`, `setVoice:name`, `stop`. */
    val calls = mutableListOf<String>()

    data class Said(val text: String, val queue: SpeakQueue, val volume: Float, val id: String)

    val said = mutableListOf<Said>()

    override fun voices(): List<EngineVoice> = listed

    override fun availability(locale: Locale): LanguageAvailability =
        answers[locale.toLanguageTag()] ?: LanguageAvailability.NOT_SUPPORTED

    override fun setLanguage(locale: Locale): Boolean {
        calls += "setLanguage:${locale.toLanguageTag()}"
        if (availability(locale) != LanguageAvailability.AVAILABLE) return false
        current = defaults[locale.toLanguageTag()]
        return true
    }

    override fun setVoice(name: String): Boolean {
        calls += "setVoice:$name"
        if (name in refused) return false
        current = name
        return true
    }

    override fun currentVoice(): EngineVoice? = listed.firstOrNull { it.name == current }

    override fun speak(text: String, queue: SpeakQueue, volume: Float, utteranceId: String) {
        said += Said(text, queue, volume, utteranceId)
    }

    override fun stop() {
        calls += "stop"
    }

    override fun shutdown() {
        calls += "shutdown"
    }

    /** The engine connects, or fails to. */
    fun becomeReady(success: Boolean = true) {
        listener?.onReady(success)
    }
}
