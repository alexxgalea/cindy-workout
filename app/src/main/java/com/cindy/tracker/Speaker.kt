package com.cindy.tracker

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Speaks rep counts and cues.
 *
 * Rep numbers are spoken with QUEUE_FLUSH so the voice tracks the athlete rather than falling
 * a queue behind during a fast set; cues that must not be dropped are queued after.
 *
 * What is said arrives as a [VoiceLine] and is worded here, by the phrasebook of the voice that is
 * actually speaking. Which voice that is, what to do when the language the athlete chose is not
 * on the phone, and how downloads and previews leave the engine are [VoiceDirector]'s business.
 * This is the Android end of it: the main thread, the background thread, and the engine.
 */
class Speaker(
    context: Context,
    private val engine: TtsEngine = AndroidTtsEngine(context),
    private val background: Executor = Executors.newSingleThreadExecutor()
) {

    private val director = VoiceDirector(engine)
    private val main = Handler(Looper.getMainLooper())

    /** Set on [shutdown], so nothing the background thread finishes late reaches a dead screen. */
    @Volatile private var closed = false

    var enabled = true

    /**
     * How loud the voice speaks, 0..1, against whatever the phone's media volume is.
     *
     * Applied per utterance rather than once at start-up, because [android.speech.tts.TextToSpeech]
     * has no volume of its own to set — `KEY_PARAM_VOLUME` is a property of the request.
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
        director.whenSpeaking = { speaking -> onSpeakingChanged?.invoke(speaking) }
    }

    // ── the language ──────────────────────────────────────────────────────────

    /**
     * The language to speak, as a [VoicePacks] tag.
     *
     * Asking for one the phone cannot speak is fine: the workout is counted in English and
     * [fallingBack] says so, and the language takes over the moment its voice turns up.
     */
    var language: String
        get() = director.wanted.tag
        set(value) = director.choose(VoicePacks.of(value))

    /** The language asked for, whether or not the phone can speak it yet. */
    val wanted: VoicePack get() = director.wanted

    /** True while the athlete is being answered in English because their language is not ready. */
    val fallingBack: Boolean get() = director.fallingBack

    /**
     * Tries the language again if it is not the one being spoken, in case its voice has arrived.
     * Cheap when nothing is wrong, so safe at every moment that might be the moment.
     */
    fun refresh() = director.refresh()

    // ── saying things ─────────────────────────────────────────────────────────

    /** Interrupts anything in progress — used for rep numbers. */
    fun say(line: VoiceLine) = speak(line, SpeakQueue.REPLACE)

    /** Queues behind whatever is speaking — used for cues that must be heard. */
    fun queue(line: VoiceLine) = speak(line, SpeakQueue.APPEND)

    /**
     * Says [line] regardless of [enabled], for previewing the voice from the menu.
     *
     * The callers are the volume slider and HEAR IT, where refusing to speak because the voice
     * is switched off would leave the athlete adjusting a number against silence.
     */
    fun preview(line: VoiceLine) = speak(line, SpeakQueue.REPLACE, ignoreEnabled = true)

    /**
     * Words the line only once the voice is going to say it. Rep counts arrive on the analysis
     * path at camera rate, and with the voice switched off there is no reason to build a
     * sentence for each one.
     */
    private fun speak(line: VoiceLine, queue: SpeakQueue, ignoreEnabled: Boolean = false) {
        if ((!enabled && !ignoreEnabled) || !director.ready) return
        director.speak(line, queue, volume)
    }

    // ── what is on the phone ──────────────────────────────────────────────────

    /**
     * Where every language stands on this phone, delivered on the main thread.
     *
     * Asked of the engine on a background thread, because listing its voices is a call into
     * another process that can take a noticeable time, and nothing is delivered once the speaker
     * has been shut down.
     */
    fun packStates(onResult: (Map<String, PackState>) -> Unit) {
        if (closed) return
        background.execute {
            val states = runCatching { director.states() }.getOrNull() ?: return@execute
            main.post { if (!closed) onResult(states) }
        }
    }

    /** Asks the engine to fetch [pack]'s voice. True if there was something to ask for. */
    fun download(pack: VoicePack): Boolean = director.download(pack)

    /** Milliseconds since [tag]'s download was asked for, or null if it has not been. */
    fun downloadingFor(tag: String): Long? = director.downloadingFor(tag)

    /**
     * Plays [pack]'s sample, in an online voice if that is the only one, without changing the
     * language chosen. A failure — no connection, data still arriving, no voice at all — arrives
     * on the main thread through [onFailure].
     */
    fun previewPack(pack: VoicePack, onFailure: (SpeechFailure) -> Unit) {
        val started = director.preview(pack, volume) { failure ->
            main.post { if (!closed) onFailure(failure) }
        }
        if (!started) onFailure(SpeechFailure.UNAVAILABLE)
    }

    fun stop() = engine.stop()

    fun shutdown() {
        closed = true
        (background as? ExecutorService)?.shutdownNow()
        engine.shutdown()
    }
}
