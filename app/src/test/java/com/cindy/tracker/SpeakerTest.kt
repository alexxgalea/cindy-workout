package com.cindy.tracker

import android.os.Looper
import android.speech.tts.TextToSpeech
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
 * The Android end of the voice: the switches, the main thread and the background one.
 *
 * The decisions themselves are [VoiceDirectorTest]'s. What is held here is what only exists on a
 * phone: that nothing is said before the engine is ready or while the voice is off, that a
 * language's answer to "where do you stand" reaches the screen on the main thread and only while
 * the screen is still there, and that the whole default stack — the real [AndroidTtsEngine]
 * behind the real speaker — says something.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SpeakerTest {

    private val engine = FakeTtsEngine()

    /** A speaker on the fake engine, whose background work runs where it is asked to. */
    private fun speaker() = Speaker(
        RuntimeEnvironment.getApplication(),
        engine,
        background = Executor { it.run() }
    )

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    // ── saying things ────────────────────────────────────────────────────────

    @Test
    fun `nothing is said before the engine is ready`() {
        val speaker = speaker()
        speaker.say(VoiceLine.Count(3))
        assertEquals(emptyList<FakeTtsEngine.Said>(), engine.said)

        engine.becomeReady()
        speaker.say(VoiceLine.Count(3))
        assertEquals("3", engine.said.single().text)
    }

    @Test
    fun `say replaces what is being said and queue waits behind it`() {
        val speaker = speaker()
        engine.becomeReady()
        speaker.say(VoiceLine.Count(3))
        speaker.queue(VoiceLine.Movement(Exercise.PUSHUP))
        assertEquals(listOf(SpeakQueue.REPLACE, SpeakQueue.APPEND), engine.said.map { it.queue })
    }

    @Test
    fun `a voice that is switched off says nothing, except to be previewed`() {
        val speaker = speaker()
        engine.becomeReady()
        speaker.enabled = false

        speaker.say(VoiceLine.Count(3))
        speaker.queue(VoiceLine.Count(4))
        assertEquals(emptyList<FakeTtsEngine.Said>(), engine.said)

        speaker.preview(VoiceLine.VolumeCheck)
        assertEquals("Three", engine.said.single().text)
    }

    @Test
    fun `the volume is held between nought and one and travels with each utterance`() {
        val speaker = speaker()
        engine.becomeReady()
        speaker.volume = 3f
        speaker.say(VoiceLine.Count(1))
        speaker.volume = -1f
        speaker.say(VoiceLine.Count(2))
        assertEquals(listOf(1f, 0f), engine.said.map { it.volume })
    }

    @Test
    fun `speech starting and stopping reaches whoever is ducking the music`() {
        val speaker = speaker()
        val seen = mutableListOf<Boolean>()
        speaker.onSpeakingChanged = { seen += it }
        engine.becomeReady()

        engine.listener!!.onStart("a")
        engine.listener!!.onDone("a")
        assertEquals(listOf(true, false), seen)
    }

    @Test
    fun `stopping stops the engine`() {
        val speaker = speaker()
        speaker.stop()
        assertTrue("stop" in engine.calls)
    }

    // ── the language ─────────────────────────────────────────────────────────

    @Test
    fun `what is said follows the language chosen`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()
        speaker.language = "es"

        speaker.say(VoiceLine.Movement(Exercise.SQUAT))
        assertEquals("sentadillas", engine.said.last().text)
        assertFalse(speaker.fallingBack)
    }

    @Test
    fun `a language the phone lacks is answered in English, and said to be`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()
        speaker.language = "ru"

        assertTrue(speaker.fallingBack)
        assertEquals("ru", speaker.wanted.tag)
        speaker.say(VoiceLine.Movement(Exercise.PUSHUP))
        assertEquals("push ups", engine.said.last().text)
    }

    @Test
    fun `refreshing picks up a voice that has arrived`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()
        speaker.language = "ru"
        assertTrue(speaker.fallingBack)

        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }
        engine.answers["ru-RU"] = LanguageAvailability.AVAILABLE
        engine.defaults["ru-RU"] = "ru-ru-x-ruc-local"
        speaker.refresh()

        assertFalse(speaker.fallingBack)
        speaker.say(VoiceLine.Movement(Exercise.PUSHUP))
        assertEquals("отжимания", engine.said.last().text)
    }

    @Test
    fun `English before the engine answers is not reported as a fall-back`() {
        engine.likeGoogle()
        val speaker = speaker()
        speaker.language = "es"
        assertFalse(speaker.fallingBack)
    }

    @Test
    fun `a tag nobody has is English`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()
        speaker.language = "klingon"
        assertEquals("en", speaker.language)
        assertFalse(speaker.fallingBack)
    }

    // ── what is on the phone ─────────────────────────────────────────────────

    @Test
    fun `where each language stands arrives on the main thread`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()

        var states: Map<String, PackState>? = null
        speaker.packStates { states = it }
        assertNull("delivered before the main thread got to it", states)

        idle()
        assertNotNull(states)
        assertEquals(PackState.READY, states!!["es"])
        assertEquals(PackState.DOWNLOADABLE, states!!["ru"])
    }

    @Test
    fun `nothing is reported before the engine has answered`() {
        // An engine that has not connected lists no voices. Reporting that would say the phone
        // speaks nothing but English, for as long as the engine took to start.
        engine.likeGoogle()
        val speaker = speaker()

        var states: Map<String, PackState>? = null
        speaker.packStates { states = it }
        idle()
        assertNull(states)

        engine.becomeReady()
        speaker.packStates { states = it }
        idle()
        assertNotNull(states)
    }

    @Test
    fun `nothing is delivered to a screen that has gone`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()

        var states: Map<String, PackState>? = null
        speaker.packStates { states = it }
        speaker.shutdown()
        idle()
        assertNull(states)

        // And a request made after the screen has gone is not made at all.
        speaker.packStates { states = it }
        idle()
        assertNull(states)
    }

    @Test
    fun `a question is not asked again while the last is still out`() {
        engine.likeGoogle()
        val queued = mutableListOf<Runnable>()
        val speaker = Speaker(
            RuntimeEnvironment.getApplication(), engine, background = Executor { queued += it }
        )
        engine.becomeReady()

        var delivered = 0
        repeat(3) { speaker.packStates { delivered++ } }
        assertEquals("three questions asked, one waiting its turn", 1, queued.size)

        queued.removeAt(0).run()
        idle()
        assertEquals("only the one that was asked is answered", 1, delivered)

        speaker.packStates { delivered++ }
        assertEquals("free to ask again once answered", 1, queued.size)
    }

    @Test
    fun `an engine that fails to answer does not stop the questions after it`() {
        engine.likeGoogle()
        var broken = true
        val flaky = object : TtsEngine by engine {
            override fun voices(): List<EngineVoice> =
                if (broken) error("the engine went away") else engine.voices()
        }
        val speaker = Speaker(
            RuntimeEnvironment.getApplication(), flaky, background = Executor { it.run() }
        )
        engine.becomeReady()

        var states: Map<String, PackState>? = null
        speaker.packStates { states = it }
        idle()
        assertNull(states)

        broken = false
        speaker.packStates { states = it }
        idle()
        assertNotNull("the question that failed left the way blocked", states)
    }

    @Test
    fun `a download is asked for and timed`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()
        assertEquals(DownloadRequest.ASKED, speaker.download(VoicePacks.of("ru")))
        assertNotNull(speaker.downloadingFor("ru"))
        assertNull(speaker.downloadingFor("es"))
    }

    @Test
    fun `a download is timed from when it was asked for`() {
        engine.likeGoogle()
        var clock = 1_000L
        val speaker = Speaker(
            RuntimeEnvironment.getApplication(),
            engine,
            background = Executor { it.run() },
            now = { clock }
        )
        engine.becomeReady()
        speaker.download(VoicePacks.of("ru"))

        clock += 90_000L
        assertEquals(90_000L, speaker.downloadingFor("ru"))
    }

    // ── previewing ───────────────────────────────────────────────────────────

    @Test
    fun `a language nothing speaks cannot be previewed, and that is said at once`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()

        var failure: SpeechFailure? = null
        val started = speaker.previewPack(VoicePacks.of("pt")) { failure = it }
        assertEquals(SpeechFailure.UNAVAILABLE, failure)
        assertFalse("said to have started, with the failure already reported", started)
    }

    @Test
    fun `a preview before the engine is ready is refused, and that is said at once`() {
        engine.likeGoogle()
        val speaker = speaker()

        var failure: SpeechFailure? = null
        val started = speaker.previewPack(VoicePacks.of("es")) { failure = it }
        assertEquals(SpeechFailure.UNAVAILABLE, failure)
        assertFalse(started)
        assertEquals(emptyList<FakeTtsEngine.Said>(), engine.said)
    }

    @Test
    fun `a preview that fails later says so on the main thread`() {
        engine.likeGoogle()
        val speaker = speaker()
        engine.becomeReady()

        var failure: SpeechFailure? = null
        val started = speaker.previewPack(VoicePacks.of("ru")) { failure = it }
        assertNull(failure)
        assertTrue("reported as not started, though it was", started)

        engine.listener!!.onError(engine.said.last().id, SpeechFailure.NETWORK)
        assertNull("reported off the main thread", failure)
        idle()
        assertEquals(SpeechFailure.NETWORK, failure)
    }

    // ── on the real engine ───────────────────────────────────────────────────

    @Test
    fun `the default stack says something once Android says it is ready`() {
        val speaker = Speaker(RuntimeEnvironment.getApplication())
        val tts = shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance())
        val seen = mutableListOf<Boolean>()
        speaker.onSpeakingChanged = { seen += it }

        speaker.say(VoiceLine.Count(3))
        assertNull("spoke before the engine was ready", tts.lastSpokenText)

        tts.onInitListener.onInit(TextToSpeech.SUCCESS)
        speaker.say(VoiceLine.Count(3))
        assertEquals("3", tts.lastSpokenText)

        idle()
        assertEquals(listOf(true, false), seen)
    }
}
