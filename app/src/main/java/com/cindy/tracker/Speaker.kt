package com.cindy.tracker

import android.content.Context
import android.os.Bundle
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

    /**
     * How loud the voice speaks, 0..1, against whatever the phone's media volume is.
     *
     * Applied per utterance rather than once at start-up, because [TextToSpeech] has no volume
     * of its own to set — [TextToSpeech.Engine.KEY_PARAM_VOLUME] is a property of the request.
     * Changing this therefore takes effect on the next thing said, which for a rep count is the
     * next rep, and is what makes the menu's slider audible while it is being dragged.
     */
    var volume = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
        }

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

    /**
     * The words each [VoiceLine] is said in. Callers hand over the fact and this decides the
     * sentence, so the words always belong to the voice that is actually speaking them.
     */
    private val phrasebook: Phrasebook = PhrasebookEn

    /** Interrupts anything in progress — used for rep numbers. */
    fun say(line: VoiceLine) = speak(phrasebook.say(line), TextToSpeech.QUEUE_FLUSH)

    /** Queues behind whatever is speaking — used for cues that must be heard. */
    fun queue(line: VoiceLine) = speak(phrasebook.say(line), TextToSpeech.QUEUE_ADD)

    /**
     * Says [line] regardless of [enabled], for previewing the voice from the menu.
     *
     * The callers are the volume slider and HEAR IT, where refusing to speak because the voice
     * is switched off would leave the athlete adjusting a number against silence.
     */
    fun preview(line: VoiceLine) =
        speak(phrasebook.say(line), TextToSpeech.QUEUE_FLUSH, ignoreEnabled = true)

    // Raw text, for the coach's strings until it speaks in lines too.
    fun say(text: String) = speak(text, TextToSpeech.QUEUE_FLUSH)
    fun queue(text: String) = speak(text, TextToSpeech.QUEUE_ADD)

    private fun speak(text: String, mode: Int, ignoreEnabled: Boolean = false) {
        if ((!enabled && !ignoreEnabled) || !ready) return
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        }
        tts?.speak(text, mode, params, "cindy-${utteranceId.incrementAndGet()}")
    }

    fun stop() = run { tts?.stop(); Unit }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
    }
}
