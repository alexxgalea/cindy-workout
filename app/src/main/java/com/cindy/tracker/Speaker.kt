package com.cindy.tracker

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

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
    private val background: Executor = Executors.newSingleThreadExecutor(),
    now: () -> Long = System::currentTimeMillis
) {

    private val director = VoiceDirector(engine, now = now)
    private val main = Handler(Looper.getMainLooper())

    /** Set on [shutdown], so nothing the background thread finishes late reaches a dead screen. */
    @Volatile private var closed = false

    /** True from the moment a question is handed to the background thread until it has been answered. */
    private val asking = AtomicBoolean(false)

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

    /**
     * True while the athlete is being answered in English because their language is not ready.
     * Only once the engine has answered; before that English is simply where everything starts.
     */
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
     *
     * Nothing is delivered before the engine has connected, either. An engine that has not
     * answered yet lists no voices, and reporting that would tell the athlete their phone speaks
     * nothing but English for as long as it took to start. The caller keeps whatever it was
     * showing and asks again.
     *
     * Asked again while the last question is still out, nothing is queued and [onResult] is not
     * called: an engine that is slow to answer is not helped by a line of identical questions
     * behind the first, whose answers would only arrive stale, one after another. The caller
     * that asks on a timer simply gets its answer on a later turn.
     */
    fun packStates(onResult: (Map<String, PackState>) -> Unit) {
        if (closed || !director.ready) return
        if (!asking.compareAndSet(false, true)) return
        background.execute {
            try {
                val states = runCatching { director.states() }.getOrNull() ?: return@execute
                main.post { if (!closed) onResult(states) }
            } finally {
                asking.set(false)
            }
        }
    }

    /**
     * Asks the engine to fetch [pack]'s voice, and says what came of it: asked, or an engine
     * that can only be asked through its own screen, or nothing to ask. See [DownloadRequest].
     */
    fun download(pack: VoicePack): DownloadRequest = director.download(pack)

    /** Milliseconds since [tag]'s download was asked for, or null if it has not been. */
    fun downloadingFor(tag: String): Long? = director.downloadingFor(tag)

    /**
     * Plays [pack]'s sample, in an online voice if that is the only one, without changing the
     * language chosen. A failure — no connection, data still arriving, no voice at all — arrives
     * on the main thread through [onFailure].
     *
     * Returns whether the engine took it. When it did not, [onFailure] has already been called,
     * so a caller that has something to say about a preview that is playing can wait for this.
     */
    fun previewPack(pack: VoicePack, onFailure: (SpeechFailure) -> Unit): Boolean {
        val started = director.preview(pack, volume) { failure ->
            main.post { if (!closed) onFailure(failure) }
        }
        if (!started) onFailure(SpeechFailure.UNAVAILABLE)
        return started
    }

    fun stop() = engine.stop()

    fun shutdown() {
        closed = true
        (background as? ExecutorService)?.shutdownNow()
        engine.shutdown()
    }
}
