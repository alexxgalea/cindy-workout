package com.cindy.tracker

import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowTextToSpeech

/**
 * The one place that knows what Android's constants mean, held to what they mean.
 *
 * Robolectric's shadow stands in for the engine, which is enough for this: what is under test is
 * the translation — a voice's features into "installed", an availability code into three states,
 * an error code into what the athlete can act on — and not the engine.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AndroidTtsEngineTest {

    /** Everything the engine reports, in order, as text. */
    private class Heard : EngineListener {
        val events = mutableListOf<String>()
        override fun onReady(success: Boolean) { events += "ready:$success" }
        override fun onStart(utteranceId: String) { events += "start:$utteranceId" }
        override fun onDone(utteranceId: String) { events += "done:$utteranceId" }
        override fun onStop(utteranceId: String) { events += "stop:$utteranceId" }
        override fun onError(utteranceId: String, failure: SpeechFailure) {
            events += "error:$utteranceId:$failure"
        }
    }

    private val heard = Heard()

    private fun newEngine() = AndroidTtsEngine(RuntimeEnvironment.getApplication())
        .also { it.listener = heard }

    private fun shadow() = shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance())

    private fun voice(
        name: String,
        tag: String,
        network: Boolean = false,
        features: Set<String> = emptySet()
    ) = Voice(name, Locale.forLanguageTag(tag), Voice.QUALITY_HIGH, Voice.LATENCY_LOW, network, features)

    @Test
    fun `it says the engine is ready when Android does, and when it gives up`() {
        newEngine()
        shadow().onInitListener.onInit(TextToSpeech.SUCCESS)
        shadow().onInitListener.onInit(TextToSpeech.ERROR)
        assertEquals(listOf("ready:true", "ready:false"), heard.events)
    }

    @Test
    fun `a connection that failed is let go of`() {
        newEngine()
        val tts = shadow()
        assertFalse(tts.isShutdown)
        tts.onInitListener.onInit(TextToSpeech.ERROR)
        assertTrue("the failed connection is still bound", tts.isShutdown)
    }

    @Test
    fun `voices are read as they are, including the ones not fetched and the ones online`() {
        val engine = newEngine()
        ShadowTextToSpeech.addVoice(voice("es-es-x-eea-local", "es-ES"))
        ShadowTextToSpeech.addVoice(
            voice("ru-ru-x-ruc-local", "ru-RU", features = setOf(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))
        )
        ShadowTextToSpeech.addVoice(voice("pl-pl-x-oda-network", "pl-PL", network = true))

        val byName = engine.voices().associateBy { it.name }
        assertEquals(
            EngineVoice(
                "es-es-x-eea-local", "es", "ES", installed = true, network = false,
                quality = Voice.QUALITY_HIGH, latency = Voice.LATENCY_LOW
            ),
            byName["es-es-x-eea-local"]
        )
        assertFalse(byName.getValue("ru-ru-x-ruc-local").installed)
        assertTrue(byName.getValue("pl-pl-x-oda-network").network)
    }

    @Test
    fun `an engine with no voices lists none`() {
        assertEquals(emptyList<EngineVoice>(), newEngine().voices())
    }

    @Test
    fun `availability comes down to the three states that matter`() {
        val engine = newEngine()
        ShadowTextToSpeech.addLanguageAvailability(Locale.forLanguageTag("es-ES"))
        assertEquals(LanguageAvailability.AVAILABLE, engine.availability(Locale.forLanguageTag("es-ES")))
        // The language without that region is still the language.
        assertEquals(LanguageAvailability.AVAILABLE, engine.availability(Locale.forLanguageTag("es-MX")))
        assertEquals(LanguageAvailability.NOT_SUPPORTED, engine.availability(Locale.forLanguageTag("ru-RU")))
    }

    @Test
    fun `a language takes when the engine has it and does not when it has not`() {
        val engine = newEngine()
        ShadowTextToSpeech.addLanguageAvailability(Locale.forLanguageTag("es-ES"))
        assertTrue(engine.setLanguage(Locale.forLanguageTag("es-ES")))
        assertFalse(engine.setLanguage(Locale.forLanguageTag("ru-RU")))
    }

    @Test
    fun `a voice is set by its name, listed first or not`() {
        val engine = newEngine()
        ShadowTextToSpeech.addVoice(voice("es-es-x-eea-local", "es-ES"))

        // Never listed by this engine object: setting it looks the voice up itself.
        assertTrue(engine.setVoice("es-es-x-eea-local"))
        assertEquals("es-es-x-eea-local", shadow().currentVoice.name)
        assertEquals("es-es-x-eea-local", engine.currentVoice()?.name)

        assertFalse(engine.setVoice("nobody"))
    }

    @Test
    fun `there is no current voice until one is set`() {
        assertNull(newEngine().currentVoice())
    }

    @Test
    fun `saying replaces or appends as asked, at the volume given`() {
        val engine = newEngine()
        engine.speak("uno", SpeakQueue.REPLACE, 0.5f, "a")
        assertEquals("uno", shadow().lastSpokenText)
        assertEquals(TextToSpeech.QUEUE_FLUSH, shadow().queueMode)

        engine.speak("dos", SpeakQueue.APPEND, 1f, "b")
        assertEquals("dos", shadow().lastSpokenText)
        assertEquals(TextToSpeech.QUEUE_ADD, shadow().queueMode)
    }

    @Test
    fun `an utterance is reported as it starts and finishes`() {
        val engine = newEngine()
        engine.speak("uno", SpeakQueue.REPLACE, 1f, "a")
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("start:a", "done:a"), heard.events)
    }

    @Test
    fun `an utterance cut off is reported as stopped, not as done`() {
        newEngine()
        shadow().utteranceProgressListener.onStop("a", true)
        assertEquals(listOf("stop:a"), heard.events)
    }

    @Test
    fun `an error says what went wrong as far as anyone can act on it`() {
        newEngine()
        val progress = shadow().utteranceProgressListener
        progress.onError("n", TextToSpeech.ERROR_NETWORK)
        progress.onError("t", TextToSpeech.ERROR_NETWORK_TIMEOUT)
        progress.onError("i", TextToSpeech.ERROR_NOT_INSTALLED_YET)
        progress.onError("o", TextToSpeech.ERROR_SYNTHESIS)
        assertEquals(
            listOf("error:n:NETWORK", "error:t:NETWORK", "error:i:NOT_INSTALLED", "error:o:OTHER"),
            heard.events
        )
    }

    @Test
    fun `shutting down stops it and lets go, and saying afterwards is harmless`() {
        val engine = newEngine()
        val tts = shadow()
        engine.shutdown()
        assertTrue(tts.isShutdown)
        engine.speak("late", SpeakQueue.REPLACE, 1f, "z")
        assertEquals(emptyList<String>(), heard.events)
    }
}
