package com.cindy.tracker

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import java.util.Locale

/**
 * A [TtsEngine] over the phone's own [TextToSpeech].
 *
 * Everything with a decision in it lives in [VoiceDirector]; this only translates. Voices become
 * [EngineVoice]s, the availability codes become [LanguageAvailability], the utterance callbacks
 * become [EngineListener] calls, and the answers that Android gives as an `int` become a
 * `Boolean`. It has to be the one place that knows what the platform's constants mean.
 */
class AndroidTtsEngine(context: Context) : TtsEngine {

    override var listener: EngineListener? = null

    private var tts: TextToSpeech? = null

    /**
     * The voices last listed, by name. [TextToSpeech.setVoice] wants the `Voice` itself and the
     * director only knows names, so the list is kept until asked for again.
     */
    @Volatile private var byName: Map<String, Voice> = emptyMap()

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            val connected = status == TextToSpeech.SUCCESS
            // A connection that failed is still bound to the engine's service. Let go of it.
            if (!connected) {
                tts?.shutdown()
                tts = null
            }
            listener?.onReady(connected)
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    listener?.onStart(utteranceId.orEmpty())
                }

                override fun onDone(utteranceId: String?) {
                    listener?.onDone(utteranceId.orEmpty())
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    listener?.onStop(utteranceId.orEmpty())
                }

                @Deprecated("required by the base class")
                override fun onError(utteranceId: String?) {
                    listener?.onError(utteranceId.orEmpty(), SpeechFailure.OTHER)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    listener?.onError(utteranceId.orEmpty(), failureOf(errorCode))
                }
            })
        }
    }

    override fun voices(): List<EngineVoice> = guarded(emptyList(), "listing voices") {
        // The engine may answer null, or nothing, before it has connected or if it is failing.
        val listed = tts?.voices?.toList().orEmpty()
        byName = listed.associateBy { it.name }
        listed.map { it.toEngineVoice() }
    }

    override fun availability(locale: Locale): LanguageAvailability =
        guarded(LanguageAvailability.NOT_SUPPORTED, "checking $locale") {
            when (tts?.isLanguageAvailable(locale)) {
                TextToSpeech.LANG_AVAILABLE,
                TextToSpeech.LANG_COUNTRY_AVAILABLE,
                TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE -> LanguageAvailability.AVAILABLE
                TextToSpeech.LANG_MISSING_DATA -> LanguageAvailability.MISSING_DATA
                else -> LanguageAvailability.NOT_SUPPORTED
            }
        }

    override fun setLanguage(locale: Locale): Boolean = guarded(false, "setting $locale") {
        (tts?.setLanguage(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED) >= TextToSpeech.LANG_AVAILABLE
    }

    override fun setVoice(name: String): Boolean = guarded(false, "setting voice $name") {
        val voice = byName[name] ?: run { voices(); byName[name] }
        voice != null && tts?.setVoice(voice) == TextToSpeech.SUCCESS
    }

    override fun currentVoice(): EngineVoice? = guarded(null, "reading the voice") {
        tts?.voice?.toEngineVoice()
    }

    override fun speak(text: String, queue: SpeakQueue, volume: Float, utteranceId: String) {
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        }
        val mode = when (queue) {
            SpeakQueue.REPLACE -> TextToSpeech.QUEUE_FLUSH
            SpeakQueue.APPEND -> TextToSpeech.QUEUE_ADD
        }
        tts?.speak(text, mode, params, utteranceId)
    }

    override fun stop() {
        tts?.stop()
    }

    override fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    /**
     * Runs a call into the engine, which is another process and is not always well behaved: some
     * throw from `getVoices`, some from `setLanguage` for a locale they half-know. None of that
     * should take the app down at the moment it starts, or cost a rep count. A call that throws
     * answers as if the engine had nothing to say.
     */
    private inline fun <T> guarded(fallback: T, what: String, call: () -> T): T =
        try {
            call()
        } catch (e: Exception) {
            Log.w(TAG, "text-to-speech engine failed $what", e)
            fallback
        }

    private fun Voice.toEngineVoice() = EngineVoice(
        name = name,
        language = locale.language,
        country = locale.country,
        // A voice the engine lists but has not fetched says so in its features.
        installed = features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) != true,
        network = isNetworkConnectionRequired,
        quality = quality,
        latency = latency
    )

    private fun failureOf(errorCode: Int): SpeechFailure = when (errorCode) {
        TextToSpeech.ERROR_NETWORK, TextToSpeech.ERROR_NETWORK_TIMEOUT -> SpeechFailure.NETWORK
        TextToSpeech.ERROR_NOT_INSTALLED_YET -> SpeechFailure.NOT_INSTALLED
        else -> SpeechFailure.OTHER
    }

    private companion object {
        const val TAG = "Cindy"
    }
}
