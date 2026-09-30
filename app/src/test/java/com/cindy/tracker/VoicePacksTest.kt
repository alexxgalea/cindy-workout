package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** The catalogue the picker is drawn from, and what a stored tag turns back into. */
class VoicePacksTest {

    @Test
    fun `English leads and the other ten follow in the order asked for`() {
        assertEquals(
            listOf("en", "es", "fr", "de", "it", "pt", "nl", "pl", "ro", "tr", "ru"),
            VoicePacks.all.map { it.tag }
        )
        assertSame(VoicePacks.english, VoicePacks.all.first())
    }

    @Test
    fun `every pack carries its own phrasebook`() {
        VoicePacks.all.forEach { assertEquals(it.tag, it.phrasebook.tag) }
    }

    @Test
    fun `tags are unique`() {
        assertEquals(VoicePacks.all.size, VoicePacks.all.map { it.tag }.toSet().size)
    }

    @Test
    fun `every pack can be named to the athlete in both languages`() {
        VoicePacks.all.forEach {
            assertTrue("${it.tag} has no native name", it.nativeName.isNotBlank())
            assertTrue("${it.tag} has no English name", it.englishName.isNotBlank())
        }
    }

    @Test
    fun `each pack asks the phone for the voice of its own region first`() {
        assertEquals("en-US", VoicePacks.english.defaultLocale.toLanguageTag())
        assertEquals("pt-BR", VoicePacks.of("pt").defaultLocale.toLanguageTag())
        VoicePacks.all.forEach {
            assertEquals(it.tag, it.defaultLocale.language)
            assertEquals(it.defaultCountry, it.defaultLocale.country)
        }
    }

    @Test
    fun `a stored tag comes back as its pack`() {
        assertSame(PhrasebookEs, VoicePacks.of("es").phrasebook)
        assertSame(PhrasebookRu, VoicePacks.of("ru").phrasebook)
    }

    @Test
    fun `a tag nobody has is English rather than a crash`() {
        assertSame(VoicePacks.english, VoicePacks.of(null))
        assertSame(VoicePacks.english, VoicePacks.of(""))
        assertSame(VoicePacks.english, VoicePacks.of("xx"))
        // A region on the end is not a tag this app stores.
        assertSame(VoicePacks.english, VoicePacks.of("es-ES"))
    }

    @Test
    fun `a pack refuses another language's phrasebook`() {
        val mismatch = runCatching { VoicePack("es", "Español", "Spanish", "ES", PhrasebookFr) }
        assertTrue(mismatch.isFailure)
    }
}
