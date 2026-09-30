package com.cindy.tracker

import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Decides which voice the workout is spoken in, and looks after the engine while it does.
 *
 * The one rule the whole thing serves: **the words and the voice always agree.** A Spanish
 * sentence in an English voice is unintelligible and an English sentence in a Spanish voice is
 * worse, so what is said is worded by the phrasebook of the voice actually in use. If the athlete
 * asks for a language the phone cannot speak — the voice has not been fetched, or the engine
 * doesn't have it — the workout carries on in English and says so, rather than failing or
 * mumbling. [wanted] keeps what they asked for, so the moment the voice arrives it takes over.
 *
 * Free of Android types, so all of that is testable against a fake engine.
 *
 * **Threads.** Everything here is for the main thread — that is where the workout's rep counts
 * are spoken from, since the analysis thread only posts a frame for the screen to render — with
 * two exceptions that are safe elsewhere: [states], which only reads, and the [EngineListener]
 * callbacks, which the engine delivers from its own threads. So the state kept here is not
 * locked, and [download] and [preview], which list the engine's voices, block for as long as
 * that takes. They answer a tap, never a rep.
 */
class VoiceDirector(
    private val engine: TtsEngine,
    private val device: () -> Locale = { Locale.getDefault() },
    private val now: () -> Long = { System.currentTimeMillis() }
) : EngineListener {

    /** True once the engine has connected. Nothing is asked of it before that. */
    @Volatile var ready = false
        private set

    /** The language the athlete asked for. */
    var wanted: VoicePack = VoicePacks.english
        private set

    /** The language actually being spoken: [wanted], or English when the phone cannot. */
    var using: VoicePack = VoicePacks.english
        private set

    /** Words for the voice in use. */
    val phrasebook: Phrasebook get() = using.phrasebook

    /**
     * True while the athlete is being answered in English because their language is not ready.
     *
     * Never true before the engine has connected: until then English is only where everything
     * starts, and reporting it as a fall-back would tell someone whose Spanish voice is installed
     * that it isn't. It is also never true for an engine that failed to connect at all, which is
     * a different problem with nothing to say about languages.
     */
    val fallingBack: Boolean get() = ready && using !== wanted

    /** Told when the engine's readiness is known. */
    var whenReady: ((Boolean) -> Unit)? = null

    /** Told when speech starts and stops, so music can duck out of its way. */
    var whenSpeaking: ((Boolean) -> Unit)? = null

    /**
     * The pack whose voice the engine is set to now, or null when something else — a preview, a
     * download request — has moved it, so that the next thing said puts it back first.
     */
    private var applied: VoicePack? = null

    private val ids = AtomicInteger(0)

    /** When each language's download was asked for. The engine cannot say; only the app knows. */
    private val downloads = ConcurrentHashMap<String, Long>()

    @Volatile private var previewId: String? = null
    @Volatile private var onPreviewFailure: ((SpeechFailure) -> Unit)? = null

    init {
        engine.listener = this
    }

    // ── which language ────────────────────────────────────────────────────────

    /**
     * Asks for [pack]. Takes effect now if the engine is ready, and as soon as it is if not.
     *
     * Asking for what is already being spoken costs the engine nothing, so this can be called
     * every time the screen comes back. Asking again for a language that had to fall back to
     * English is a retry, which is how a voice that has just been fetched gets picked up.
     */
    fun choose(pack: VoicePack) {
        val unchanged = pack === wanted
        wanted = pack
        if (ready && (!unchanged || fallingBack)) apply()
    }

    /**
     * Tries again, if the language asked for is not the one being spoken.
     *
     * Cheap when nothing is wrong, so it is safe to call at every moment a voice might have
     * arrived: coming back to the screen, and starting a workout.
     */
    fun refresh() {
        if (fallingBack) apply()
    }

    private fun apply() {
        if (applyTo(wanted)) {
            using = wanted
        } else {
            applyTo(VoicePacks.english)
            using = VoicePacks.english
        }
        applied = using
    }

    /** Puts the engine on [pack]'s voice. False if the phone has none that can count a workout. */
    private fun applyTo(pack: VoicePack): Boolean {
        if (pack.tag == VoicePacks.english.tag) {
            // Exactly what the app did before it had languages: the engine's own US voice.
            engine.setLanguage(Locale.US)
            return true
        }
        val voices = engine.voices()
        val best = VoiceChoice.bestForWorkout(pack, voices, device())
        if (best == null) {
            // An engine that lists no voice for a language may still speak it, and says so
            // only when asked. What it lists is otherwise believed over what it says.
            return voices.none { it.speaks(pack) } &&
                engine.availability(pack.defaultLocale) == LanguageAvailability.AVAILABLE &&
                engine.setLanguage(pack.defaultLocale)
        }
        // Ask for the language first, so the engine picks the voice the athlete has chosen in
        // the system settings, and only take the choice out of its hands if that voice is not
        // one a workout can be counted with — a network voice, or one whose data is missing.
        if (engine.setLanguage(pack.defaultLocale) && engine.currentVoice()?.countsFor(pack) == true) {
            return true
        }
        return engine.setVoice(best.name)
    }

    // ── speaking ──────────────────────────────────────────────────────────────

    /**
     * Says [line] in the voice in use and returns the utterance's id.
     *
     * Puts the engine back on the athlete's voice first if a preview has moved it, and only then
     * words the line, because putting it back can turn out to fall back to English.
     */
    fun speak(line: VoiceLine, queue: SpeakQueue, volume: Float): String {
        if (applied !== using) apply()
        val id = "cindy-${ids.incrementAndGet()}"
        engine.speak(phrasebook.say(line), queue, volume, id)
        return id
    }

    /**
     * Plays [pack]'s sample in a voice for it, without changing which language is chosen.
     *
     * Uses the voice a workout would if the phone has one, so the preview is a true sample, and
     * an online voice otherwise, so a language can be heard before it is downloaded. Returns
     * false if nothing on the engine speaks it. A failure once it is playing — no connection,
     * data still arriving — comes back through [onFailure], from whatever thread the engine uses.
     */
    fun preview(pack: VoicePack, volume: Float, onFailure: (SpeechFailure) -> Unit): Boolean {
        if (!ready) return false
        val voice = VoiceChoice.bestForPreview(pack, engine.voices(), device())
        // Whatever comes of it, the engine may no longer be on the athlete's voice.
        applied = null
        val accepted = when {
            voice != null -> engine.setVoice(voice.name)
            pack.tag == VoicePacks.english.tag -> engine.setLanguage(Locale.US)
            engine.availability(pack.defaultLocale) == LanguageAvailability.AVAILABLE ->
                engine.setLanguage(pack.defaultLocale)
            else -> false
        }
        if (!accepted) return false

        val id = "preview-${ids.incrementAndGet()}"
        previewId = id
        onPreviewFailure = onFailure
        engine.speak(pack.phrasebook.say(VoiceLine.Sample), SpeakQueue.REPLACE, volume, id)
        return true
    }

    // ── what is on the phone ──────────────────────────────────────────────────

    /**
     * Where every language stands, keyed by tag. Blocks on the engine, so not for the main thread.
     *
     * A finished download is forgotten here, since a language that is ready needs no reminder
     * that it was once asked for.
     */
    fun states(): Map<String, PackState> {
        val voices = engine.voices()
        val states = LinkedHashMap<String, PackState>()
        for (pack in VoicePacks.all) {
            // Only ask an engine what it can speak when its own list gives no answer.
            val availability =
                if (voices.any { it.countsFor(pack) }) null else engine.availability(pack.defaultLocale)
            // containsKey, not `in`: on a ConcurrentHashMap `in` asks about the values.
            val downloading = downloads.containsKey(pack.tag)
            val state = VoiceChoice.stateOf(pack, voices, availability, downloading)
            if (state == PackState.READY) downloads.remove(pack.tag)
            states[pack.tag] = state
        }
        return states
    }

    /**
     * Asks the engine to fetch [pack]'s voice, and says what came of it.
     *
     * The only documented way to ask is to set a voice whose data is missing, so that is all
     * this claims to have done: [DownloadRequest.ASKED]. An engine that says the data is missing
     * without listing a voice to set cannot be asked from here, and pretending otherwise would
     * leave the athlete watching "downloading" for something nobody requested. That is
     * [DownloadRequest.USE_ENGINE_SCREEN], for the caller to send them to the engine's own
     * installer.
     *
     * The engine reports no progress, so a request only starts the clock: [states] shows the
     * language as downloading until its voice turns up, and [downloadingFor] says for how long,
     * which is the only way to tell a slow download from one that is waiting for Wi-Fi.
     */
    fun download(pack: VoicePack): DownloadRequest {
        if (!ready) return DownloadRequest.NOT_OFFERED
        val voice = VoiceChoice.bestToDownload(pack, engine.voices(), device())
        if (voice == null) {
            return if (engine.availability(pack.defaultLocale) == LanguageAvailability.MISSING_DATA) {
                DownloadRequest.USE_ENGINE_SCREEN
            } else {
                DownloadRequest.NOT_OFFERED
            }
        }

        // Asking moves the engine onto a voice that cannot speak yet, and a voice whose data is
        // missing may answer "error" while the request goes through, so the answer is not used.
        applied = null
        engine.setVoice(voice.name)
        downloads[pack.tag] = now()
        apply()
        return DownloadRequest.ASKED
    }

    /** Milliseconds since [tag]'s download was asked for, or null if it has not been. */
    fun downloadingFor(tag: String): Long? = downloads[tag]?.let { now() - it }

    // ── the engine's side ─────────────────────────────────────────────────────

    override fun onReady(success: Boolean) {
        ready = success
        if (success) apply()
        whenReady?.invoke(success)
    }

    override fun onStart(utteranceId: String) {
        whenSpeaking?.invoke(true)
    }

    override fun onDone(utteranceId: String) {
        whenSpeaking?.invoke(false)
        if (utteranceId == previewId) forgetPreview()
    }

    override fun onStop(utteranceId: String) {
        // Cut off by the next thing said, or by stop(). Not "done" as far as the music is
        // concerned — a rep count flushing the last one would otherwise let it swell between
        // every pair of numbers — but a preview that was cut off is over, and its callback,
        // which holds on to a screen, should not outlive it.
        if (utteranceId == previewId) forgetPreview()
    }

    override fun onError(utteranceId: String, failure: SpeechFailure) {
        whenSpeaking?.invoke(false)
        if (utteranceId == previewId) {
            val report = onPreviewFailure
            forgetPreview()
            report?.invoke(failure)
        }
    }

    private fun forgetPreview() {
        previewId = null
        onPreviewFailure = null
    }
}
