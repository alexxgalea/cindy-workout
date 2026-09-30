package com.cindy.tracker

import com.cindy.tracker.LanguageAvailability.AVAILABLE
import com.cindy.tracker.LanguageAvailability.MISSING_DATA
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The speaker's decisions, driven against an engine that does what real ones do.
 *
 * The rule under all of them is that the words and the voice agree: what is said is worded by
 * the phrasebook of the voice actually in use, so a language the phone cannot speak is answered
 * in English, whole, and not in a foreign voice reading the wrong sentences.
 */
class VoiceDirectorTest {

    private val en = VoicePacks.english
    private val es = VoicePacks.of("es")
    private val ru = VoicePacks.of("ru")
    private val pt = VoicePacks.of("pt")

    private val engine = FakeTtsEngine()
    private var clock = 0L
    private val director = VoiceDirector(engine, device = { EngineFixtures.britain }, now = { clock })

    private fun googlePhone() = engine.likeGoogle()

    private fun saidFor(line: VoiceLine): String {
        director.speak(line, SpeakQueue.APPEND, 1f)
        return engine.said.last().text
    }

    // ── the engine's readiness ───────────────────────────────────────────────

    @Test
    fun `nothing is asked of the engine before it is ready`() {
        googlePhone()
        director.choose(es)
        assertEquals(emptyList<String>(), engine.calls)
        assertFalse(director.ready)
    }

    @Test
    fun `a failed engine is never asked anything`() {
        engine.becomeReady(success = false)
        director.choose(es)
        assertEquals(emptyList<String>(), engine.calls)
        assertFalse(director.ready)
    }

    @Test
    fun `readiness is passed on`() {
        var told: Boolean? = null
        director.whenReady = { told = it }
        engine.becomeReady(success = false)
        assertEquals(false, told)
        engine.becomeReady(success = true)
        assertEquals(true, told)
    }

    @Test
    fun `English is the engine's own US voice, as it always was`() {
        googlePhone()
        engine.becomeReady()
        assertEquals(listOf("setLanguage:en-US"), engine.calls)
        assertSame(en, director.using)
        assertFalse(director.fallingBack)
    }

    @Test
    fun `a language chosen before the engine is ready is applied when it is`() {
        googlePhone()
        director.choose(es)
        engine.becomeReady()
        assertSame(es, director.using)
        assertEquals(listOf("setLanguage:es-ES"), engine.calls)
    }

    // ── choosing the voice ───────────────────────────────────────────────────

    @Test
    fun `the engine's own choice for a language is kept when it can count a workout`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        // Asked for the language and nothing else, so the voice set in the system settings stands.
        assertEquals(listOf("setLanguage:en-US", "setLanguage:es-ES"), engine.calls)
        assertSame(es, director.using)
        assertFalse(director.fallingBack)
    }

    @Test
    fun `a network voice the engine defaults to is replaced with a local one`() {
        googlePhone()
        engine.defaults["es-ES"] = "es-es-x-eea-network"
        engine.becomeReady()
        director.choose(es)
        assertEquals(
            listOf("setLanguage:en-US", "setLanguage:es-ES", "setVoice:es-es-x-eea-local"),
            engine.calls
        )
        assertSame(es, director.using)
    }

    @Test
    fun `a voice installed under another region is used when the default region is not`() {
        engine.listed = listOf(EngineFixtures.voice("es-us-x-sfb-local", "es", "US"))
        engine.answers["es-ES"] = MISSING_DATA
        engine.becomeReady()
        director.choose(es)
        assertEquals("setVoice:es-us-x-sfb-local", engine.calls.last())
        assertSame(es, director.using)
    }

    @Test
    fun `an engine that lists no voices is asked whether it speaks the language`() {
        engine.listed = emptyList()
        engine.answers["es-ES"] = AVAILABLE
        engine.answers["ru-RU"] = MISSING_DATA
        engine.becomeReady()

        director.choose(es)
        assertSame(es, director.using)
        assertEquals("setLanguage:es-ES", engine.calls.last())

        director.choose(ru)
        assertSame(en, director.using)
    }

    // ── the words follow the voice ───────────────────────────────────────────

    @Test
    fun `what is said is worded for the voice in use`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        val id = director.speak(VoiceLine.Movement(Exercise.SQUAT), SpeakQueue.APPEND, 0.5f)
        assertEquals(FakeTtsEngine.Said("sentadillas", SpeakQueue.APPEND, 0.5f, id), engine.said.single())
    }

    @Test
    fun `a language the phone cannot speak is answered in English and remembered`() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)

        assertSame(ru, director.wanted)
        assertSame(en, director.using)
        assertTrue(director.fallingBack)
        // The engine is left on English, not on a Russian voice that cannot speak yet.
        assertEquals("setLanguage:en-US", engine.calls.last())
        assertEquals("push ups", saidFor(VoiceLine.Movement(Exercise.PUSHUP)))
    }

    @Test
    fun `it takes over as soon as the voice arrives`() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)
        assertTrue(director.fallingBack)

        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }
        engine.answers["ru-RU"] = AVAILABLE
        engine.defaults["ru-RU"] = "ru-ru-x-ruc-local"
        director.refresh()

        assertSame(ru, director.using)
        assertFalse(director.fallingBack)
        assertEquals("отжимания", saidFor(VoiceLine.Movement(Exercise.PUSHUP)))
    }

    @Test
    fun `asking again for the language already spoken costs the engine nothing`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        val before = engine.calls.toList()
        director.choose(es)
        assertEquals(before, engine.calls)
    }

    @Test
    fun `asking again for a language that fell back is a retry`() {
        googlePhone()
        engine.becomeReady()
        director.choose(ru)
        val before = engine.calls.size
        director.choose(ru)
        assertTrue("no retry was made", engine.calls.size > before)
    }

    @Test
    fun `refreshing changes nothing when there is nothing to fix`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        val before = engine.calls.toList()
        director.refresh()
        assertEquals(before, engine.calls)
    }

    // ── previewing ───────────────────────────────────────────────────────────

    @Test
    fun `a preview is the sample in the language, in a voice for it`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)

        assertTrue(director.preview(ru, 1f) {})
        // Russian is not fetched, so the only voice that can play it is the online one.
        assertEquals("setVoice:ru-ru-x-ruc-network", engine.calls.last())
        assertEquals("Три. Четыре. Пять. Отжимания.", engine.said.last().text)
        assertEquals(SpeakQueue.REPLACE, engine.said.last().queue)
    }

    @Test
    fun `a preview uses the local voice when there is one`() {
        googlePhone()
        engine.becomeReady()
        assertTrue(director.preview(es, 1f) {})
        assertEquals("setVoice:es-es-x-eea-local", engine.calls.last())
    }

    @Test
    fun `a preview leaves the chosen language as it was`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        director.preview(ru, 1f) {}

        // The next thing the workout says puts the athlete's own voice back first.
        val spoken = saidFor(VoiceLine.Movement(Exercise.PUSHUP))
        assertEquals("flexiones", spoken)
        assertEquals("setLanguage:es-ES", engine.calls.last())
        assertSame(es, director.using)
    }

    @Test
    fun `a preview that cannot reach the network says so, once, for its own utterance`() {
        googlePhone()
        engine.becomeReady()
        var failure: SpeechFailure? = null
        director.preview(ru, 1f) { failure = it }
        val id = engine.said.last().id

        engine.listener!!.onError("someone-else", SpeechFailure.NETWORK)
        assertNull(failure)

        engine.listener!!.onError(id, SpeechFailure.NETWORK)
        assertEquals(SpeechFailure.NETWORK, failure)

        failure = null
        engine.listener!!.onError(id, SpeechFailure.NETWORK)
        assertNull("reported a second time", failure)
    }

    @Test
    fun `a preview of a language nothing speaks is refused`() {
        googlePhone()
        engine.becomeReady()
        assertFalse(director.preview(pt, 1f) {})
        assertEquals(emptyList<FakeTtsEngine.Said>(), engine.said)
    }

    @Test
    fun `a preview before the engine is ready is refused`() {
        googlePhone()
        assertFalse(director.preview(es, 1f) {})
    }

    // ── downloading ──────────────────────────────────────────────────────────

    @Test
    fun `a download asks for the voice that has not been fetched, then puts the engine back`() {
        googlePhone()
        engine.becomeReady()
        director.choose(es)
        clock = 1_000L

        assertTrue(director.download(ru))

        val calls = engine.calls
        assertEquals("setVoice:ru-ru-x-ruc-local", calls[calls.size - 2])
        assertEquals("setLanguage:es-ES", calls.last())
        assertEquals(PackState.DOWNLOADING, director.states()["ru"])

        clock = 61_000L
        assertEquals(60_000L, director.downloadingFor("ru"))
    }

    @Test
    fun `a download reports success even when the engine says the voice failed to set`() {
        // Setting a voice whose data is missing is what asks for it, and engines answer "error"
        // while the request goes through.
        googlePhone()
        engine.refused += "ru-ru-x-ruc-local"
        engine.becomeReady()
        assertTrue(director.download(ru))
        assertEquals(PackState.DOWNLOADING, director.states()["ru"])
    }

    @Test
    fun `with no voice listed the engine is asked for the language`() {
        engine.listed = emptyList()
        engine.answers["ru-RU"] = MISSING_DATA
        engine.becomeReady()

        assertTrue(director.download(ru))
        assertTrue("setLanguage:ru-RU" in engine.calls)
        assertEquals(PackState.DOWNLOADING, director.states()["ru"])
    }

    @Test
    fun `there is nothing to ask for when the engine does not offer the language`() {
        googlePhone()
        engine.becomeReady()
        assertFalse(director.download(pt))
        assertNull(director.downloadingFor("pt"))
    }

    @Test
    fun `a download that has arrived is forgotten`() {
        googlePhone()
        engine.becomeReady()
        director.download(ru)

        engine.listed = EngineFixtures.google.map {
            if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it
        }
        assertEquals(PackState.READY, director.states()["ru"])
        assertNull(director.downloadingFor("ru"))
    }

    // ── what is on the phone ─────────────────────────────────────────────────

    @Test
    fun `every language is accounted for, in the order they are listed`() {
        googlePhone()
        engine.becomeReady()
        val states = director.states()

        assertEquals(VoicePacks.all.map { it.tag }, states.keys.toList())
        assertEquals(PackState.READY, states["en"])
        assertEquals(PackState.READY, states["es"])
        assertEquals(PackState.DOWNLOADABLE, states["ru"])
        assertEquals(PackState.ONLINE_ONLY, states["pl"])
        assertEquals(PackState.UNSUPPORTED, states["pt"])
    }

    // ── the speaking hooks ───────────────────────────────────────────────────

    @Test
    fun `speech starting and stopping is passed on`() {
        val seen = mutableListOf<Boolean>()
        director.whenSpeaking = { seen += it }
        engine.becomeReady()

        engine.listener!!.onStart("a")
        engine.listener!!.onDone("a")
        engine.listener!!.onStart("b")
        engine.listener!!.onError("b", SpeechFailure.OTHER)
        assertEquals(listOf(true, false, true, false), seen)
    }
}
