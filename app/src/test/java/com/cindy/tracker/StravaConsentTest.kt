package com.cindy.tracker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

/**
 * The sheet that comes before Strava's consent page, from each of the three roads that lead to it.
 *
 * What these hold is the order of things: the sheet first, and nothing minted, stored or opened
 * until Strava's own button is tapped. A NOT NOW that left a pending state behind, or a road that
 * skipped the sheet, would put Cindy back to sending the athlete to Strava with no word of what
 * follows.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaConsentTest {

    private fun context(): Context = ApplicationProvider.getApplicationContext()
    private val tokens get() = StravaTokenStore(context())

    @After
    fun reset() {
        StravaConfig.availableForTest = null
        tokens.clearGrant()
        tokens.pendingState = null
        tokens.afterConnectUploadAtMillis = null
        StravaUploads.clear(context())
    }

    private fun descendants(root: View): List<View> = buildList {
        add(root)
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(descendants(root.getChildAt(i)))
    }

    private fun byDescriptionPrefix(root: View, prefix: String): View? =
        descendants(root).firstOrNull { it.contentDescription?.toString()?.startsWith(prefix) == true }

    private fun byText(root: View, text: String): View? =
        descendants(root).firstOrNull { it is TextView && it.text.toString() == text }

    private fun sheet(): View? =
        ShadowDialog.getLatestDialog()?.takeIf { it.isShowing }?.window?.decorView

    private fun sheetText(): String =
        descendants(sheet()!!).filterIsInstance<TextView>().joinToString("\n") { it.text }

    private fun menu(): Activity {
        StravaConfig.availableForTest = true
        return Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context(), workoutLive = false)
        ).setup().get()
    }

    private fun attempt(atMillis: Long) = Attempt(
        rounds = 1, reps = 0, atMillis = atMillis, durationMs = 20 * 60 * 1_000L, countedReps = 30,
        setSplits = listOf(
            SetSplit(Exercise.PULLUP, 1_000L, 5, 0),
            SetSplit(Exercise.PUSHUP, 1_000L, 10, 0),
            SetSplit(Exercise.SQUAT, 1_000L, 15, 0)
        ),
        profile = CindyProfile.STANDARD
    )

    private fun results(atMillis: Long): Activity {
        WorkManagerTestInitHelper.initializeTestWorkManager(context())
        val intent = ResultsActivity.intent(context(), attempt(atMillis), stoppedEarly = false)
        return Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
    }

    private fun assertNothingStarted(activity: Activity) {
        assertNull("something was opened", shadowOf(activity).nextStartedActivity)
        assertNull("a state was minted", tokens.pendingState)
    }

    // ---- the menu ---------------------------------------------------------------------------

    @Test
    fun `the menu row asks first, and says what is sent and what is not`() {
        val activity = menu()
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Not connected")!!.performClick()

        assertNotNull("no sheet", sheet())
        val text = sheetText()
        for (phrase in listOf(
            "Connect to Strava",
            "Nothing is sent until you connect.",
            "Its score and every set with its reps.",
            "Your heart rate, if a watch recorded it.",
            "Never the camera picture, the video or the pose.",
            StravaConsent.DATA_PERMISSIONS
        )) {
            assertTrue("the sheet lost: $phrase", text.contains(phrase))
        }
        assertNotNull("no official button", byDescriptionPrefix(sheet()!!, StravaConsent.CONNECT_LABEL))
        assertNothingStarted(activity)
        activity.finish()
    }

    @Test
    fun `NOT NOW from the menu starts nothing`() {
        val activity = menu()
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Not connected")!!.performClick()

        byText(sheet()!!, "NOT NOW")!!.performClick()
        assertNothingStarted(activity)
        activity.finish()
    }

    @Test
    fun `Connect with Strava from the menu opens Strava's page for the state it stored`() {
        val activity = menu()
        tokens.afterConnectUploadAtMillis = 999L // left behind by an earlier results screen
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Not connected")!!.performClick()

        byDescriptionPrefix(sheet()!!, StravaConsent.CONNECT_LABEL)!!.performClick()

        val started = shadowOf(activity).nextStartedActivity
        assertNotNull("nothing was opened", started)
        assertEquals(Intent.ACTION_VIEW, started.action)
        val state = tokens.pendingState
        assertNotNull(state)
        assertEquals(StravaAuth.authorizeUri(state!!), started.dataString)
        assertNull("a menu connect is about no particular attempt", tokens.afterConnectUploadAtMillis)
        activity.finish()
    }

    // ---- the results screen -----------------------------------------------------------------

    @Test
    fun `Connect to upload asks first, and connects for that attempt only after Connect with Strava`() {
        StravaConfig.availableForTest = true
        val activity = results(301L)
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Connect to upload")!!.performClick()

        assertTrue(sheetText().contains("Nothing is sent until you connect."))
        assertNothingStarted(activity)
        assertNull(tokens.afterConnectUploadAtMillis)

        byDescriptionPrefix(sheet()!!, StravaConsent.CONNECT_LABEL)!!.performClick()
        val started = shadowOf(activity).nextStartedActivity
        assertNotNull(started)
        assertEquals(StravaAuth.authorizeUri(tokens.pendingState!!), started.dataString)
        assertEquals(301L, tokens.afterConnectUploadAtMillis)
        activity.finish()
    }

    @Test
    fun `NOT NOW from the results row connects nothing and remembers no attempt`() {
        StravaConfig.availableForTest = true
        val activity = results(302L)
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Connect to upload")!!.performClick()

        byText(sheet()!!, "NOT NOW")!!.performClick()
        assertNothingStarted(activity)
        assertNull(tokens.afterConnectUploadAtMillis)
        activity.finish()
    }

    @Test
    fun `Reconnect to upload asks first too`() {
        StravaConfig.availableForTest = true
        tokens.grant = StravaGrant(
            accessToken = "a", refreshToken = "r", expiresAtEpochS = 9_999_999_999L,
            scopes = setOf("read", "activity:write"), athleteName = "Alex G"
        )
        StravaUploads.write(context(), 303L, StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT))
        val activity = results(303L)
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Reconnect to upload")!!.performClick()

        assertNotNull("no sheet before reconnecting", sheet())
        assertNothingStarted(activity)

        byDescriptionPrefix(sheet()!!, StravaConsent.CONNECT_LABEL)!!.performClick()
        assertNotNull(shadowOf(activity).nextStartedActivity)
        assertEquals(303L, tokens.afterConnectUploadAtMillis)
        activity.finish()
    }

    @Test
    fun `a connected athlete is not asked again from the menu, and sees the Compatible with Strava mark`() {
        tokens.grant = StravaGrant(
            accessToken = "a", refreshToken = "r", expiresAtEpochS = 9_999_999_999L,
            scopes = setOf("read", "activity:write"), athleteName = "Alex G"
        )
        val activity = menu()
        byDescriptionPrefix(activity.findViewById(android.R.id.content), "Strava, Connected")!!.performClick()

        assertNotNull(sheet())
        assertFalse("the connected sheet is not the consent sheet", sheetText().contains("Connect to Strava"))
        // The mark that names the integration, on the sheet that is open while it is in use.
        assertNotNull(byDescriptionPrefix(sheet()!!, StravaConsent.COMPATIBLE_LABEL))
        activity.finish()
    }
}
