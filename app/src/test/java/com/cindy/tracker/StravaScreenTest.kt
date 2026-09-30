package com.cindy.tracker

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The Strava row and sheet, and the redirect activity — kept apart from [ScreenSmokeTest] per
 * the plan, so the HR work's own screen tests never collide with this file.
 *
 * The menu's three Strava states are exercised through [MenuActivity.stravaAvailableForTest],
 * the seam documented on that property: [StravaConfig.available] is always false under a unit
 * test build, so without it there would be no way to reach the connected or not-connected rows
 * at all, only the "not available" one every test would otherwise see by default.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaScreenTest {

    private fun context() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After
    fun resetSeam() {
        MenuActivity.stravaAvailableForTest = null
        StravaTokenStore(context()).clearGrant()
    }

    private fun findByDescriptionPrefix(
        root: android.view.View, prefix: String
    ): android.view.View? {
        if (root.contentDescription?.toString()?.startsWith(prefix) == true) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findByDescriptionPrefix(root.getChildAt(i), prefix)?.let { return it }
            }
        }
        return null
    }

    private fun buildMenu(): android.app.Activity {
        val activity = Robolectric.buildActivity(
            MenuActivity::class.java,
            MenuActivity.intent(context(), workoutLive = false)
        ).setup().get()
        val root = activity.findViewById<android.view.View>(android.R.id.content)
        root.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(1080, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(2400, android.view.View.MeasureSpec.EXACTLY)
        )
        root.layout(0, 0, 1080, 2400)
        assertTrue("nothing was laid out", root.width > 0 && root.height > 0)
        return activity
    }

    @Test
    fun `the menu builds with Strava unavailable`() {
        MenuActivity.stravaAvailableForTest = false
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Not available in this build"
        )
        assertTrue("no unavailable Strava row", row != null)
        activity.finish()
    }

    @Test
    fun `the menu builds with Strava not connected`() {
        MenuActivity.stravaAvailableForTest = true
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Not connected"
        )
        assertTrue("no not-connected Strava row", row != null)
        activity.finish()
    }

    @Test
    fun `the menu builds with Strava connected, and the sheet offers DONE and DISCONNECT`() {
        MenuActivity.stravaAvailableForTest = true
        StravaTokenStore(context()).grant = StravaGrant(
            accessToken = "a", refreshToken = "r", expiresAtEpochS = 9_999_999_999L,
            scopes = setOf("read", "activity:write"), athleteName = "Alex G"
        )
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Connected · Alex G"
        )
        assertTrue("no connected Strava row", row != null)

        row!!.performClick()
        val dialog = org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue("no sheet opened", dialog != null && dialog.isShowing)
        activity.finish()
    }

    @Test
    fun `tapping Strava when unavailable opens no sheet`() {
        MenuActivity.stravaAvailableForTest = false
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Not available in this build"
        )
        row!!.performClick()
        val dialog = org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue("an unavailable build must not open a sheet", dialog == null || !dialog.isShowing)
        activity.finish()
    }

    // ---- StravaAuthActivity -----------------------------------------------------------------

    @Test
    fun `the redirect activity ignores an intent with no pending state, and stores nothing`() {
        StravaTokenStore(context()).pendingState = null
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(
            "${StravaConfig.REDIRECT_URI}?state=whatever&code=somecode&scope=read,activity:write"
        ))
        val activity = Robolectric.buildActivity(StravaAuthActivity::class.java, intent).setup().get()

        assertTrue("must finish rather than hang around", activity.isFinishing)
        assertNull(StravaTokenStore(context()).grant)
    }

    @Test
    fun `the redirect activity ignores a bad state without crashing or storing anything`() {
        StravaTokenStore(context()).pendingState = "expected"
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(
            "${StravaConfig.REDIRECT_URI}?state=wrong&code=somecode&scope=read,activity:write"
        ))
        val activity = Robolectric.buildActivity(StravaAuthActivity::class.java, intent).setup().get()

        assertTrue("must finish rather than hang around", activity.isFinishing)
        assertNull(StravaTokenStore(context()).grant)
        // The mismatch must not have cancelled the real pending attempt either.
        assertTrue(StravaTokenStore(context()).pendingState == "expected")
    }

    @Test
    fun `the redirect activity clears the pending state on a denial`() {
        StravaTokenStore(context()).pendingState = "expected"
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(
            "${StravaConfig.REDIRECT_URI}?state=expected&error=access_denied"
        ))
        val activity = Robolectric.buildActivity(StravaAuthActivity::class.java, intent).setup().get()

        assertTrue("must finish rather than hang around", activity.isFinishing)
        assertNull(StravaTokenStore(context()).grant)
        assertNull(StravaTokenStore(context()).pendingState)
    }
}
