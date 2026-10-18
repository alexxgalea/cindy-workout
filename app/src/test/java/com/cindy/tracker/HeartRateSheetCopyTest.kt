package com.cindy.tracker

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

/**
 * What the heart-rate sheet tells the athlete about where the reading goes.
 *
 * It said "Nothing is uploaded" in a build whose uploads carry the heart-rate trace, which is the
 * one claim in the app the privacy policy and the Data safety answers contradict.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HeartRateSheetCopyTest {

    @After
    fun restore() {
        StravaConfig.availableForTest = null
    }

    private fun descendants(root: View): List<View> = buildList {
        add(root)
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(descendants(root.getChildAt(i)))
    }

    /** The text of the sheet's intro line, after opening the menu's Heart rate row. */
    private fun intro(): String {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val root = menu.findViewById<View>(android.R.id.content)
        descendants(root).first {
            it.contentDescription?.toString()?.startsWith("Heart rate") == true
        }.performClick()
        val sheet = ShadowDialog.getLatestDialog()!!.window!!.decorView
        val line = descendants(sheet)
            .filterIsInstance<TextView>()
            .firstOrNull { it.text.toString().startsWith("Reads the heart rate") }
        assertNotNull("the sheet has no intro line", line)
        menu.finish()
        return line!!.text.toString()
    }

    @Test
    fun `without Strava the heart rate stays on the phone`() {
        StravaConfig.availableForTest = false
        val text = intro()
        assertTrue(text, text.endsWith("It stays on this phone."))
        assertFalse(text, text.contains("Strava"))
    }

    @Test
    fun `with Strava it says an upload carries the heart rate`() {
        StravaConfig.availableForTest = true
        val text = intro()
        assertTrue(text, text.contains("except in a workout you upload to Strava"))
    }

    @Test
    fun `no build says nothing is uploaded`() {
        for (strava in listOf(false, true)) {
            StravaConfig.availableForTest = strava
            assertFalse(intro().contains("Nothing is uploaded"))
        }
    }
}
