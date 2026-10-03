package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The licences have to travel with the app, and Help has to credit what each one covers. These
 * hold the two lists to each other, so a credit cannot name a licence whose text is not shipped
 * and a shipped text cannot go uncredited.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LicencesTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `every licence's full text ships in the app, and is that licence`() {
        val markers = mapOf(
            Licences.APACHE to listOf("Apache License", "Version 2.0, January 2004", "END OF TERMS AND CONDITIONS"),
            Licences.OFL to listOf("SIL OPEN FONT LICENSE Version 1.1", "PERMISSION & CONDITIONS", "OTHER DEALINGS IN THE FONT SOFTWARE.")
        )
        assertEquals("a licence has no markers here", Licences.all.toSet(), markers.keys)
        for ((licence, expected) in markers) {
            val text = Licences.text(context, licence)
            assertTrue("${licence.name} is empty", text.isNotBlank())
            for (marker in expected) {
                assertTrue("${licence.name} is missing '$marker'", text.contains(marker))
            }
        }
    }

    @Test
    fun `every credit names a licence that ships, and every shipped licence is credited`() {
        for (credit in Licences.credits) {
            assertTrue("${credit.what} names a licence that is not shipped", credit.licence in Licences.all)
        }
        for (licence in Licences.all) {
            assertTrue(
                "${licence.name} ships but covers nothing",
                Licences.credits.any { it.licence == licence }
            )
        }
    }

    @Test
    fun `the font's notice in the credit is the notice its licence text opens with`() {
        val manrope = Licences.credits.single { it.licence == Licences.OFL }
        val firstLine = Licences.text(context, Licences.OFL).lines().first()
        assertEquals(manrope.by, firstLine)
    }
}
