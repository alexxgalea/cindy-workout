package com.cindy.tracker

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Speaks rep counts and cues.
 *
 * Rep numbers are spoken with QUEUE_FLUSH so the voice tracks the athlete rather than falling
 * a queue behind during a fast set; cues that must not be dropped are queued after.
 *
 * Rep numbers are also kept as sound and played straight from memory when one is scored
 * ([CountClip]): the phone's engine is otherwise heard about half a second after it is asked, most
 * of it silence at the start of each word. They are captured from the engine's own synthesis, by
 * saying each at no volume while nothing else is being said, and from every number still spoken
 * live. A number not captured yet, or a phone whose engine hands over no audio, is spoken as
 * before. A cue queued while a kept number plays waits for it to finish, as it would behind the
 * engine's own speech, and nothing audible ever waits behind a capture.
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
    now: () -> Long = System::currentTimeMillis,
    private val player: ClipPlayer = AudioTrackClipPlayer()
) {

    private val director = VoiceDirector(engine, now = now)
    private val main = Handler(Looper.getMainLooper())

    /** Set on [shutdown], so nothing the background thread finishes late reaches a dead screen. */
    @Volatile private var closed = false

    /** True from the moment a question is handed to the background thread until it has been answered. */
    private val asking = AtomicBoolean(false)

    /** Kept rep numbers, by count, for the voice of [clipsEpoch]. */
    private val clips = ConcurrentHashMap<Int, CountClip>()
    @Volatile private var clipsEpoch = -1
    private val clipIds = AtomicInteger(0)

    /** A number whose audio is arriving: which, for which voice, and the audio so far. */
    private class Capture(val reps: Int, val epoch: Int, val silent: Boolean) {
        val audio = ByteArrayOutputStream()
        var sampleRate = 0
    }

    /** Numbers being captured, silently or as they are spoken, by utterance id. */
    private val captures = ConcurrentHashMap<String, Capture>()

    /** Silent captures cut short in a row; past [MAX_CUT_SHORT] only live speech fills the gaps. */
    @Volatile private var cutShort = 0

    /** Whether the engine is saying something now, as far as its own callbacks tell. */
    @Volatile private var engineSpeaking = false

    /** When the kept number playing now ends, on [SystemClock.uptimeMillis]; 0 when none is. */
    @Volatile private var clipEndsAt = 0L
    private val clipEnded = Runnable {
        clipEndsAt = 0L
        onSpeakingChanged?.invoke(false)
    }

    /** The token of cues held until a kept number has finished, and of a capture put off. */
    private val held = Any()

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

    /**
     * Told, by the id [say] returned, when an utterance starts to sound (true) or is cut off before
     * it finished (false). From the engine's thread. The debug trace times the spoken count with it.
     */
    var onUtterance: ((String, Boolean) -> Unit)? = null

    init {
        director.whenSpeaking = { speaking ->
            engineSpeaking = speaking
            onSpeakingChanged?.invoke(speaking)
        }
        director.whenUtterance = { id, started -> onUtterance?.invoke(id, started) }
        director.whenAudio = { id, rate, pcm ->
            captures[id]?.let { c ->
                synchronized(c) {
                    if (c.sampleRate == 0) c.sampleRate = rate
                    if (rate == c.sampleRate) c.audio.write(pcm) else captures.remove(id)
                }
            }
        }
        director.whenFinished = { id, finished -> captures.remove(id)?.let { keep(it, finished) } }
        director.whenReady = { ready -> if (ready) main.post { prepareCounts() } }
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
        set(value) {
            director.choose(VoicePacks.of(value))
            prepareCounts()
        }

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
    fun refresh() {
        director.refresh()
        prepareCounts()
    }

    // ── saying things ─────────────────────────────────────────────────────────

    /**
     * Interrupts anything in progress — used for rep numbers. Returns the utterance's id, or null
     * when nothing was said.
     */
    fun say(line: VoiceLine): String? {
        if (!enabled || !director.ready) return null
        val clip = (line as? VoiceLine.Count)?.let { clipFor(it.reps) }
        if (clip != null) {
            cancelHeld()
            engine.stop()
            if (player.play(clip, volume)) return clipStarted(clip)
        }
        // Kept as it is spoken, so the next time this number comes round it is ready.
        val epoch = director.epoch
        return speak(line, SpeakQueue.REPLACE) { id ->
            if (line is VoiceLine.Count) captures[id] = Capture(line.reps, epoch, silent = false)
        }
    }

    /**
     * Queues behind whatever is speaking — used for cues that must be heard. Behind a kept
     * number the cue is held until the number ends, and returns null.
     */
    fun queue(line: VoiceLine): String? {
        // Silent captures are queued only when nothing else is, so dropping them cuts nothing off.
        if (enabled && director.ready && director.capturingNow) engine.stop()
        if (enabled && director.ready && clipEndsAt > SystemClock.uptimeMillis()) {
            main.postAtTime({ speak(line, SpeakQueue.APPEND) }, held, clipEndsAt)
            return null
        }
        return speak(line, SpeakQueue.APPEND)
    }

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
    private fun speak(
        line: VoiceLine,
        queue: SpeakQueue,
        ignoreEnabled: Boolean = false,
        register: ((String) -> Unit)? = null
    ): String? {
        if ((!enabled && !ignoreEnabled) || !director.ready) return null
        if (queue == SpeakQueue.REPLACE) {
            cancelHeld()
            stopClip()
        }
        return director.speak(line, queue, volume, register)
    }

    // ── kept numbers ──────────────────────────────────────────────────────────

    /** How many rep numbers are ready to play in the voice in use. */
    val countsPrepared: Int get() = if (clipsEpoch == director.epoch) clips.size else 0

    /** The kept [reps], if it was captured in the voice in use. */
    private fun clipFor(reps: Int): CountClip? =
        if (clipsEpoch == director.epoch) clips[reps] else null

    private fun clipStarted(clip: CountClip): String {
        val id = "clip-${clipIds.incrementAndGet()}"
        main.removeCallbacks(clipEnded)
        clipEndsAt = SystemClock.uptimeMillis() + clip.durationMs
        main.postAtTime(clipEnded, clipEndsAt)
        onSpeakingChanged?.invoke(true)
        onUtterance?.invoke(id, true)
        return id
    }

    private fun stopClip() {
        if (clipEndsAt == 0L) return
        player.stop()
        main.removeCallbacks(clipEnded)
        clipEnded.run()
    }

    private fun cancelHeld() = main.removeCallbacksAndMessages(held)

    /** A capture that ended: kept if it finished, in the voice still in use, with audio in it. */
    private fun keep(capture: Capture, finished: Boolean) {
        if (capture.silent) {
            if (finished) {
                cutShort = 0
            } else if (++cutShort <= MAX_CUT_SHORT) {
                // Flushed by something said, or by the engine itself; try again once it is quiet.
                main.removeCallbacksAndMessages(preparing)
                main.postAtTime({ prepareCounts() }, preparing, SystemClock.uptimeMillis() + PREPARE_RETRY_MS)
            }
        }
        if (!finished || capture.epoch != director.epoch) return
        val clip = synchronized(capture) {
            if (capture.sampleRate == 0) return
            CountClip.fromPcm16(capture.sampleRate, capture.audio.toByteArray())
        }.trimmed()
        if (clip.samples.isEmpty()) return
        if (clipsEpoch == capture.epoch) clips[capture.reps] = clip
    }

    /**
     * Captures, silently, the rep numbers the voice in use does not have yet. Cheap when they are
     * all there, so it is called whenever the voice might have changed. Main thread.
     *
     * Each is said at no volume, queued in the engine, and only while nothing is being said, so
     * anything said after flushes them rather than waiting behind them (see [queue]). Whatever a
     * flush cut short is captured the next time this is called, or as it is spoken live.
     */
    fun prepareCounts() {
        if (closed || !director.ready) return
        val epoch = director.epoch
        if (clipsEpoch != epoch) {
            clips.clear()
            clipsEpoch = epoch
        }
        if (director.capturingNow) return
        if (engineSpeaking || clipEndsAt != 0L) {
            main.removeCallbacksAndMessages(preparing)
            main.postAtTime({ prepareCounts() }, preparing, SystemClock.uptimeMillis() + PREPARE_RETRY_MS)
            return
        }
        for (n in 1..PREPARED_COUNTS) {
            if (clips.containsKey(n)) continue
            var registered: String? = null
            val id = director.capture(VoiceLine.Count(n)) {
                registered = it
                captures[it] = Capture(n, epoch, silent = true)
            }
            if (id == null) {
                registered?.let { captures.remove(it) }
                break
            }
        }
    }

    /** The token of a capture put off because something was being said. */
    private val preparing = Any()

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

    fun stop() {
        engine.stop()
        cancelHeld()
        stopClip()
    }

    fun shutdown() {
        closed = true
        cancelHeld()
        main.removeCallbacksAndMessages(preparing)
        stopClip()
        (background as? ExecutorService)?.shutdownNow()
        player.release()
        engine.shutdown()
    }

    private companion object {
        /**
         * A Cindy movement asks for at most 15; a single-movement set past this keeps each number
         * the first time it is spoken.
         */
        const val PREPARED_COUNTS = 30
        const val PREPARE_RETRY_MS = 2_000L
        const val MAX_CUT_SHORT = 5
    }
}
