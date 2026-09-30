package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the language list tells the athlete about their phone, and when. */
class VoiceLanguageTextTest {

    private val es = VoicePacks.of("es")
    private val minute = 60_000L

    @Test
    fun `every state says something different`() {
        val said = PackState.entries.map { VoiceLanguageText.caption(it, null, 0L) }
        assertEquals(said.size, said.toSet().size)
        said.forEach { assertTrue(it.isNotBlank()) }
    }

    @Test
    fun `a language nobody has heard back about is being checked`() {
        assertEquals("Checking…", VoiceLanguageText.caption(null, null, waitedMs = 0L))
        assertEquals("Checking…", VoiceLanguageText.caption(null, null, waitedMs = 5_999L))
    }

    @Test
    fun `an engine that never answers is said not to be answering`() {
        assertEquals(
            "This phone's voice engine isn't answering",
            VoiceLanguageText.caption(null, null, waitedMs = VoiceLanguageText.NO_ANSWER_AFTER_MS)
        )
    }

    @Test
    fun `a download is under way until it has gone on suspiciously long`() {
        assertEquals("Downloading…", VoiceLanguageText.caption(PackState.DOWNLOADING, 0L, 0L))
        assertEquals("Downloading…", VoiceLanguageText.caption(PackState.DOWNLOADING, 2 * minute - 1, 0L))
        assertEquals(
            "Still waiting. The voice engine may need Wi-Fi.",
            VoiceLanguageText.caption(PackState.DOWNLOADING, 2 * minute, 0L)
        )
    }

    @Test
    fun `an online-only language says counting stays in English`() {
        assertTrue("English" in VoiceLanguageText.caption(PackState.ONLINE_ONLY, null, 0L))
    }

    @Test
    fun `only a language the engine does not speak cannot be chosen`() {
        PackState.entries.forEach {
            assertEquals(it != PackState.UNSUPPORTED, VoiceLanguageText.selectable(it))
        }
        // Unknown is choosable: the engine being slow should not make the list unusable.
        assertTrue(VoiceLanguageText.selectable(null))
    }

    @Test
    fun `a preview is labelled online unless the voice is on the phone`() {
        assertNull(VoiceLanguageText.previewNote(PackState.READY))
        assertNull(VoiceLanguageText.previewNote(null))
        assertEquals("Playing an online preview", VoiceLanguageText.previewNote(PackState.DOWNLOADABLE))
        assertEquals("Playing an online preview", VoiceLanguageText.previewNote(PackState.ONLINE_ONLY))
        assertEquals("Playing an online preview", VoiceLanguageText.previewNote(PackState.DOWNLOADING))
    }

    @Test
    fun `a language the engine does not speak has no preview to label`() {
        assertNull(VoiceLanguageText.previewNote(PackState.UNSUPPORTED))
    }

    @Test
    fun `every way a preview can fail is said in words the athlete can act on`() {
        assertEquals(
            "The Spanish preview needs an internet connection",
            VoiceLanguageText.previewFailure(SpeechFailure.NETWORK, es)
        )
        assertEquals(
            "The Spanish voice is still downloading",
            VoiceLanguageText.previewFailure(SpeechFailure.NOT_INSTALLED, es)
        )
        assertEquals(
            "This phone's voice engine can't play Spanish",
            VoiceLanguageText.previewFailure(SpeechFailure.UNAVAILABLE, es)
        )
        assertEquals("The preview didn't play", VoiceLanguageText.previewFailure(SpeechFailure.OTHER, es))
        SpeechFailure.entries.forEach {
            assertFalse(VoiceLanguageText.previewFailure(it, es).isBlank())
        }
    }

    @Test
    fun `an engine that has not answered is starting, and then is not answering`() {
        assertEquals(
            "The voice engine is still starting. Try again in a moment.",
            VoiceLanguageText.engineSilent(0L)
        )
        assertEquals(
            "The voice engine is still starting. Try again in a moment.",
            VoiceLanguageText.engineSilent(VoiceLanguageText.NO_ANSWER_AFTER_MS - 1)
        )
        // The same words the rows use, so the sheet does not say two things about one engine.
        assertEquals(
            VoiceLanguageText.caption(null, null, VoiceLanguageText.NO_ANSWER_AFTER_MS),
            VoiceLanguageText.engineSilent(VoiceLanguageText.NO_ANSWER_AFTER_MS)
        )
    }

    @Test
    fun `a screen reader hears the language, how it stands, and whether it is chosen`() {
        assertEquals("Español, Spanish, Ready", VoiceLanguageText.description(es, "Ready", chosen = false))
        assertEquals(
            "Español, Spanish, Ready, selected",
            VoiceLanguageText.description(es, "Ready", chosen = true)
        )
        assertEquals("Hear Spanish", VoiceLanguageText.previewDescription(es, PackState.READY))
        assertEquals("Hear Spanish", VoiceLanguageText.previewDescription(es, null))
    }

    @Test
    fun `the preview button of a language that is not offered does not sound like one that works`() {
        assertEquals(
            "Hear Spanish, not offered by this phone's voice engine",
            VoiceLanguageText.previewDescription(es, PackState.UNSUPPORTED)
        )
    }

    @Test
    fun `a language that cannot be chosen says why and what might help`() {
        val said = VoiceLanguageText.unsupportedNotice(es)
        assertTrue(said, "Spanish" in said)
        assertTrue(said, "speech settings" in said)
    }
}
