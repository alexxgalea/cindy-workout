package com.cindy.tracker

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

/**
 * Speaks rep counts and cues.
 *
 * Rep numbers are spoken with QUEUE_FLUSH so the voice tracks the athlete rather than falling
 * a queue behind during a fast set; cues that must not be dropped are queued after.
 */
class Speaker(context: Context) {

    private var tts: TextToSpeech? = null
    private var ready = false
    private val utteranceId = AtomicInteger(0)

    var enabled = true

    /** Raised while speech is audible, so background music can duck out of the way. */
    var onSpeakingChanged: ((Boolean) -> Unit)? = null

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                ready = true
            }
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) = post(true)
                override fun onDone(id: String?) = post(false)
                @Deprecated("required by the base class")
                override fun onError(id: String?) = post(false)
                override fun onError(id: String?, code: Int) = post(false)
                private fun post(speaking: Boolean) {
                    onSpeakingChanged?.invoke(speaking)
                }
            })
        }
    }

    /** Interrupts anything in progress — used for rep numbers. */
    fun say(text: String) = speak(text, TextToSpeech.QUEUE_FLUSH)

    /** Queues behind whatever is speaking — used for cues that must be heard. */
    fun queue(text: String) = speak(text, TextToSpeech.QUEUE_ADD)

    private fun speak(text: String, mode: Int) {
        if (!enabled || !ready) return
        tts?.speak(text, mode, null, "cindy-${utteranceId.incrementAndGet()}")
    }

    fun stop() = run { tts?.stop(); Unit }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
    }
}
