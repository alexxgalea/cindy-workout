package com.cindy.tracker

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
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
            listener?.onReady(status == TextToSpeech.SUCCESS)
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    listener?.onStart(utteranceId.orEmpty())
                }

                override fun onDone(utteranceId: String?) {
                    listener?.onDone(utteranceId.orEmpty())
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

    override fun voices(): List<EngineVoice> {
        // The engine may answer null, or nothing, before it has connected or if it is failing.
        val listed = tts?.voices?.toList().orEmpty()
        byName = listed.associateBy { it.name }
        return listed.map { it.toEngineVoice() }
    }

    override fun availability(locale: Locale): LanguageAvailability =
        when (tts?.isLanguageAvailable(locale)) {
            TextToSpeech.LANG_AVAILABLE,
            TextToSpeech.LANG_COUNTRY_AVAILABLE,
            TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE -> LanguageAvailability.AVAILABLE
            TextToSpeech.LANG_MISSING_DATA -> LanguageAvailability.MISSING_DATA
            else -> LanguageAvailability.NOT_SUPPORTED
        }

    override fun setLanguage(locale: Locale): Boolean =
        (tts?.setLanguage(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED) >= TextToSpeech.LANG_AVAILABLE

    override fun setVoice(name: String): Boolean {
        val voice = byName[name] ?: run { voices(); byName[name] } ?: return false
        return tts?.setVoice(voice) == TextToSpeech.SUCCESS
    }

    override fun currentVoice(): EngineVoice? = tts?.voice?.toEngineVoice()

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
}
