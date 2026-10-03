package com.cindy.tracker

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * What Help says has to stay true of the app. Each phrase below once described a control that
 * has since moved or changed, and a Help screen that describes something that is not there is
 * worse than none.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HelpScreenTest {

    private fun helpText(): String {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        val text = texts(help.findViewById<View>(android.R.id.content)).joinToString("\n")
        help.finish()
        return text
    }

    /** [StravaConfig.availableForTest] is a static that outlives the activity under test. */
    @After
    fun resetStravaSeam() {
        StravaConfig.availableForTest = null
    }

    private fun byDescriptionPrefix(root: View, prefix: String): View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is ViewGroup) for (i in 0 until root.childCount) {
            byDescriptionPrefix(root.getChildAt(i), prefix)?.let { return it }
        }
        return null
    }

    private fun texts(root: View): List<String> = buildList {
        if (root is TextView) add(root.text.toString())
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(texts(root.getChildAt(i)))
    }

    @Test
    fun `Help no longer describes controls that have moved`() {
        val text = helpText()
        for (stale in listOf(
            // Voice is a menu row with its own language and volume, not a chip on the camera.
            "VOICE turns that off",
            // +1 has no long press; SKIP is a control of its own.
            "Hold +1",
            // A paired watch's heart rate now drives the estimate.
            "Without a heart-rate strap there is no honest way",
            // The screen is called Progress, and the ladder is the level on the session page.
            "RECORDS",
            // The scaled movements are counted now.
            "use the +1 and −1 buttons if you are working at the scaled version"
        )) {
            assertFalse("Help still says: $stale", text.contains(stale))
        }
    }

    @Test
    fun `Help has a section for each part of the app it describes`() {
        val text = helpText()
        for (heading in listOf(
            "VOICE AND MUSIC", "FILMING", "THE SESSION PAGE", "COMPARING SESSIONS",
            "WHAT YOU LIFTED", "HEART RATE", "YOU AND YOUR BADGES", "REMINDERS", "PRIVACY"
        )) {
            assertTrue("Help has no $heading section", text.contains(heading))
        }
    }

    @Test
    fun `Help ends with the version the build was made as`() {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        // The scrolling content, not the buttons pinned under it.
        val last = texts(help.findViewById<View>(R.id.sections)).filter { it.isNotBlank() }.last()
        help.finish()
        assertTrue(
            "the last line of the page should be the version, not '$last'",
            last == "Cindy ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        )
    }

    @Test
    fun `Help talks about Strava only in a build that has it`() {
        StravaConfig.availableForTest = true
        val with = helpText()
        assertTrue(with.contains("STRAVA"))
        assertTrue(with.contains("the calorie estimate and the Strava upload."))
        // The flow Help describes is the one the app has: a sheet first, then Strava's button.
        assertTrue(with.contains("A sheet first says what each workout will send"))
        assertTrue(with.contains("tap Connect with Strava there"))
        assertTrue(with.contains("a View on Strava link to the activity"))

        StravaConfig.availableForTest = false
        val without = helpText()
        assertFalse("a build without Strava still has a STRAVA section", without.contains("STRAVA"))
        assertFalse("a build without Strava still mentions it", without.contains("Strava"))
        // The sentence it replaces still reads as one.
        assertTrue(without.contains("how long the camera lost you and the calorie estimate."))
    }

    @Test
    fun `Help says what stays on the phone, and how to delete it`() {
        val text = helpText()
        for (phrase in listOf(
            "PRIVACY",
            "The camera picture is read on the phone and thrown away. It is never saved or sent.",
            "There are no ads, no analytics, no account and no server of Cindy's.",
            "CLEAR on the Progress screen",
            "REMOVE on the Account screen"
        )) {
            assertTrue("the PRIVACY section lost: $phrase", text.contains(phrase))
        }
    }

    @Test
    fun `the privacy policy row opens the policy in a browser`() {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        val row = byDescriptionPrefix(help.findViewById(android.R.id.content), "Privacy policy")
        assertNotNull("no Privacy policy row", row)
        row!!.performClick()

        val started = shadowOf(help).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, started.action)
        assertEquals(AppLinks.PRIVACY_POLICY, started.dataString)
        help.finish()
    }

    @Test
    fun `the Strava paragraph of the privacy section is there when the build has Strava, and not otherwise`() {
        val marker = "Strava is the one thing that leaves the phone"

        StravaConfig.availableForTest = false
        assertFalse(helpText().contains(marker))

        StravaConfig.availableForTest = true
        val text = helpText()
        assertTrue(text.contains(marker))
        // What an upload carries, in the words the policy uses.
        assertTrue(text.contains("the heart-rate trace if a watch recorded one"))
        assertTrue(text.contains("Never video, never the pose."))
    }

    @Test
    fun `Help credits what it is built on, and a licence row shows the full text`() {
        val help = Robolectric.buildActivity(HelpActivity::class.java).setup().get()
        val text = texts(help.findViewById<View>(android.R.id.content)).joinToString("\n")
        assertTrue(text.contains("LICENCES"))
        for (credit in Licences.credits) {
            assertTrue("no credit for ${credit.what}", text.contains("${credit.what}. ${credit.by}. ${credit.licence.name}."))
        }

        val row = byDescriptionPrefix(help.findViewById(android.R.id.content), "Apache License 2.0")
        assertNotNull("no Apache License 2.0 row", row)
        row!!.performClick()

        val dialog = org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue("the licence did not open a sheet", dialog != null && dialog.isShowing)
        val sheet = texts(dialog.window!!.decorView).joinToString("\n")
        assertTrue(sheet.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
        help.finish()
    }

    @Test
    fun `Help says Cindy is independent of CrossFit and is not a medical device`() {
        val text = helpText()
        assertTrue(text.contains(
            "Cindy Tracker is an independent app. It is not affiliated with or endorsed by " +
                "CrossFit, LLC. CrossFit is a registered trademark of CrossFit, LLC."
        ))
        assertTrue(text.contains(
            "Heart rate, zones and calories here are training estimates. Cindy is not a " +
                "medical device."
        ))
    }

    @Test
    fun `CrossFit's words are still quoted as they were`() {
        val text = helpText()
        for (quote in listOf(
            "Complete as many rounds and reps as possible in 20 minutes of: " +
                "5 pull-ups, 10 push-ups, 15 squats",
            "The fastest athletes will complete rounds in under 45 seconds.",
            "Adhering to the full range of motion in all movements is important for " +
                "structural integrity and joint health."
        )) {
            assertTrue("a CrossFit quotation changed: $quote", text.contains(quote))
        }
    }
}
