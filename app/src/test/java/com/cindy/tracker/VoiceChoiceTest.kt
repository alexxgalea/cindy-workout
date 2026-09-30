package com.cindy.tracker

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Choosing a voice against the shapes real engines return.
 *
 * The fixtures ([EngineFixtures]) are modelled on what the engines on Android phones actually
 * list: Google's lists hundreds of voices, installed and not, local and network, several per
 * language; Samsung's lists what is installed and little else; and some engines list nothing and
 * answer only when asked whether a language is available.
 */
class VoiceChoiceTest {

    private val es = VoicePacks.of("es")
    private val ru = VoicePacks.of("ru")
    private val pl = VoicePacks.of("pl")
    private val pt = VoicePacks.of("pt")

    private val britain = EngineFixtures.britain
    private val google = EngineFixtures.google

    private fun voice(
        name: String,
        language: String,
        country: String = "",
        installed: Boolean = true,
        network: Boolean = false,
        quality: Int = 400,
        latency: Int = 200
    ) = EngineFixtures.voice(name, language, country, installed, network, quality, latency)

    // ── where each language stands ───────────────────────────────────────────

    @Test
    fun `an installed local voice makes a language ready`() {
        assertEquals(PackState.READY, VoiceChoice.stateOf(es, google, null, downloading = false))
    }

    @Test
    fun `a language whose local voice is not fetched can be downloaded`() {
        assertEquals(PackState.DOWNLOADABLE, VoiceChoice.stateOf(ru, google, null, downloading = false))
    }

    @Test
    fun `a download that was asked for shows as under way until the voice arrives`() {
        assertEquals(PackState.DOWNLOADING, VoiceChoice.stateOf(ru, google, null, downloading = true))
        // Once it is installed the request no longer matters.
        val arrived = google.map { if (it.name == "ru-ru-x-ruc-local") it.copy(installed = true) else it }
        assertEquals(PackState.READY, VoiceChoice.stateOf(ru, arrived, null, downloading = true))
    }

    @Test
    fun `a language spoken only over the network is online only`() {
        assertEquals(PackState.ONLINE_ONLY, VoiceChoice.stateOf(pl, google, null, downloading = false))
    }

    @Test
    fun `a language nobody lists is unsupported`() {
        assertEquals(PackState.UNSUPPORTED, VoiceChoice.stateOf(pt, google, null, downloading = false))
        assertEquals(PackState.UNSUPPORTED, VoiceChoice.stateOf(pt, emptyList(), null, downloading = false))
    }

    @Test
    fun `a voice list is trusted over the availability codes`() {
        // The engine claims Polish is available because it can reach a network voice. It is not
        // something to count a workout with.
        assertEquals(
            PackState.ONLINE_ONLY,
            VoiceChoice.stateOf(pl, google, LanguageAvailability.AVAILABLE, downloading = false)
        )
    }

    @Test
    fun `an engine that lists no voice for a language is asked instead`() {
        val listsNothing = listOf(voice("en-US-language", "en", "US"))
        assertEquals(
            PackState.READY,
            VoiceChoice.stateOf(es, listsNothing, LanguageAvailability.AVAILABLE, downloading = false)
        )
        assertEquals(
            PackState.DOWNLOADABLE,
            VoiceChoice.stateOf(es, listsNothing, LanguageAvailability.MISSING_DATA, downloading = false)
        )
        assertEquals(
            PackState.DOWNLOADING,
            VoiceChoice.stateOf(es, listsNothing, LanguageAvailability.MISSING_DATA, downloading = true)
        )
        assertEquals(
            PackState.UNSUPPORTED,
            VoiceChoice.stateOf(es, listsNothing, LanguageAvailability.NOT_SUPPORTED, downloading = false)
        )
        assertEquals(PackState.UNSUPPORTED, VoiceChoice.stateOf(es, listsNothing, null, downloading = false))
    }

    // ── which voice counts a workout ─────────────────────────────────────────

    @Test
    fun `a workout is counted with an installed local voice`() {
        assertEquals("es-es-x-eea-local", VoiceChoice.bestForWorkout(es, google, britain)?.name)
    }

    @Test
    fun `a network voice never counts a workout`() {
        assertNull(VoiceChoice.bestForWorkout(pl, google, britain))
    }

    @Test
    fun `a voice that has not been fetched never counts a workout`() {
        assertNull(VoiceChoice.bestForWorkout(ru, google, britain))
    }

    @Test
    fun `nothing is chosen from an engine that lists nothing`() {
        assertNull(VoiceChoice.bestForWorkout(es, emptyList(), britain))
    }

    @Test
    fun `the phone's own region wins when it is the same language`() {
        // A phone set to Spanish in the United States is answered in that voice, not Spain's.
        val spanishInTheUs = Locale.forLanguageTag("es-US")
        assertEquals("es-us-x-sfb-local", VoiceChoice.bestForWorkout(es, google, spanishInTheUs)?.name)
    }

    @Test
    fun `the pack's own region is next`() {
        assertEquals("ES", VoiceChoice.bestForWorkout(es, google, britain)?.country)
    }

    @Test
    fun `a phone set to another language does not sway the choice`() {
        // A Russian phone with a Spanish workout: its region is not a hint about Spanish.
        assertEquals("ES", VoiceChoice.bestForWorkout(es, google, Locale.forLanguageTag("ru-RU"))?.country)
    }

    @Test
    fun `then the faster voice, then the better one, then the name`() {
        val fast = voice("es-es-b", "es", "ES", latency = 100, quality = 300)
        val slow = voice("es-es-a", "es", "ES", latency = 300, quality = 500)
        assertEquals("es-es-b", VoiceChoice.bestForWorkout(es, listOf(slow, fast), britain)?.name)

        val better = voice("es-es-b", "es", "ES", quality = 500)
        val worse = voice("es-es-a", "es", "ES", quality = 300)
        assertEquals("es-es-b", VoiceChoice.bestForWorkout(es, listOf(worse, better), britain)?.name)

        val second = voice("es-es-b", "es", "ES")
        val first = voice("es-es-a", "es", "ES")
        assertEquals("es-es-a", VoiceChoice.bestForWorkout(es, listOf(second, first), britain)?.name)
    }

    @Test
    fun `regions compare without regard to case`() {
        val lower = voice("es-es-x", "es", "es")
        assertEquals("es-es-x", VoiceChoice.bestForWorkout(es, listOf(lower), britain)?.name)
    }

    @Test
    fun `a three letter language code is still Spanish`() {
        val samsung = voice("spa-ESP-language", "spa", "ESP")
        assertEquals("spa-ESP-language", VoiceChoice.bestForWorkout(es, listOf(samsung), britain)?.name)
    }

    @Test
    fun `English is chosen like any other language`() {
        assertEquals("en-us-x-tpd-local", VoiceChoice.bestForWorkout(VoicePacks.english, google, britain)?.name)
    }

    // ── which voice to fetch, and which to preview with ──────────────────────

    @Test
    fun `the voice to fetch is a local one that has not been`() {
        assertEquals("ru-ru-x-ruc-local", VoiceChoice.bestToDownload(ru, google, britain)?.name)
        assertEquals("es-us-x-esc-local", VoiceChoice.bestToDownload(es, google, britain)?.name)
    }

    @Test
    fun `there is nothing to fetch for a language that is only online or not offered`() {
        assertNull(VoiceChoice.bestToDownload(pl, google, britain))
        assertNull(VoiceChoice.bestToDownload(pt, google, britain))
    }

    @Test
    fun `a preview uses the voice a workout would, if there is one`() {
        assertEquals("es-es-x-eea-local", VoiceChoice.bestForPreview(es, google, britain)?.name)
    }

    @Test
    fun `a preview falls back to a network voice so a language can be heard before it is fetched`() {
        assertEquals("ru-ru-x-ruc-network", VoiceChoice.bestForPreview(ru, google, britain)?.name)
        assertEquals("pl-pl-x-oda-network", VoiceChoice.bestForPreview(pl, google, britain)?.name)
    }

    @Test
    fun `a language nothing speaks cannot be previewed`() {
        assertNull(VoiceChoice.bestForPreview(pt, google, britain))
    }
}
