package com.cindy.tracker

import java.util.Locale

/** How an utterance joins what the engine is already saying. */
enum class SpeakQueue {
    /** Cuts off whatever is being said: for a rep number, which must not fall behind the athlete. */
    REPLACE,
    /** Waits its turn: for a cue that must not be dropped. */
    APPEND
}

/** Why an utterance could not be spoken, as far as anyone can do anything about it. */
enum class SpeechFailure {
    /** A voice that runs on the engine's servers could not reach them. */
    NETWORK,
    /** The voice's data is still being fetched. */
    NOT_INSTALLED,
    /** The engine has no voice that speaks the language at all. */
    UNAVAILABLE,
    /** Anything else. */
    OTHER
}

/** What came of asking the engine to fetch a language's voice. */
enum class DownloadRequest {
    /** A voice the engine lists was set, which is the documented way to ask for its data. */
    ASKED,
    /**
     * The engine says the data is missing but lists no voice to set. Only its own screen can
     * fetch it, so the caller should send the athlete there.
     */
    USE_ENGINE_SCREEN,
    /** The engine does not offer the language, or is not ready, so there is nothing to fetch. */
    NOT_OFFERED
}

/** What an engine reports back: when it is ready, and how each utterance goes. */
interface EngineListener {
    /** The engine has connected ([success]) or has failed to and never will. */
    fun onReady(success: Boolean)
    fun onStart(utteranceId: String)
    fun onDone(utteranceId: String)
    /** Cut off before it finished, by the next utterance or by a stop. */
    fun onStop(utteranceId: String)
    fun onError(utteranceId: String, failure: SpeechFailure)
}

/**
 * What the app needs from a text-to-speech engine, and nothing more.
 *
 * The Android implementation is [AndroidTtsEngine]. It is an interface because the interesting
 * part of the speaker — which voice to use, what to do when the chosen one is missing, how a
 * download and a preview leave the engine — has to be tested against the awkward things real
 * engines do, and a `TextToSpeech` cannot be made to do them on the JVM.
 *
 * Every call may block on the engine's process, so none is free to make in a loop.
 */
interface TtsEngine {

    /** Told about readiness and utterances. Set once, by whoever owns the engine. */
    var listener: EngineListener?

    /** Every voice the engine lists, or none if it lists none or is not answering. */
    fun voices(): List<EngineVoice>

    /** Whether the engine can speak [locale], without changing anything. */
    fun availability(locale: Locale): LanguageAvailability

    /**
     * Puts the engine on [locale], letting it choose its own default voice for it, which is how
     * the voice the athlete has set in the system settings is honoured. True if it took.
     */
    fun setLanguage(locale: Locale): Boolean

    /**
     * Puts the engine on the voice called [name], one of those [voices] listed. True if it took.
     * For a voice whose data is missing this is also what asks the engine to fetch it, and may
     * report failure while doing so.
     */
    fun setVoice(name: String): Boolean

    /** The voice the engine would speak with now, if it says. */
    fun currentVoice(): EngineVoice?

    fun speak(text: String, queue: SpeakQueue, volume: Float, utteranceId: String)

    fun stop()

    fun shutdown()
}
