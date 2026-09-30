package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The voice's language as the profile keeps it: English until chosen, and never an error. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProfileVoiceLanguageTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `it is English until another is chosen`() {
        assertEquals("en", Profile(context).voiceLanguage)
    }

    @Test
    fun `a chosen language is remembered`() {
        Profile(context).voiceLanguage = "es"
        assertEquals("es", Profile(context).voiceLanguage)
    }

    @Test
    fun `a language this version does not have reads back as English`() {
        context.getSharedPreferences("cindy", Context.MODE_PRIVATE)
            .edit().putString("voice_language", "xx").commit()
        assertEquals("en", Profile(context).voiceLanguage)
    }

    @Test
    fun `a language with a region is stored as the language`() {
        Profile(context).voiceLanguage = "pt-BR"
        assertEquals("pt", Profile(context).voiceLanguage)
    }

    @Test
    fun `setting something nobody has stores English rather than the junk`() {
        Profile(context).voiceLanguage = "klingon"
        assertEquals("en", Profile(context).voiceLanguage)
    }
}
