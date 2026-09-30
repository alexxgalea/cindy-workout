package com.cindy.tracker

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The Strava row and sheet, and the redirect activity — kept apart from [ScreenSmokeTest], so
 * that file's own additions and these never collide.
 *
 * The menu's three Strava states are exercised through [StravaConfig.availableForTest], the
 * seam documented on that property: [StravaConfig.available] is always false under a unit
 * test build, so without it there would be no way to reach the connected or not-connected rows
 * at all, only the "not available" one every test would otherwise see by default.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaScreenTest {

    private fun context() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After
    fun resetSeam() {
        StravaConfig.availableForTest = null
        StravaTokenStore(context()).clearGrant()
        StravaUploads.clear(context())
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
        StravaConfig.availableForTest = false
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Not available in this build"
        )
        assertTrue("no unavailable Strava row", row != null)
        activity.finish()
    }

    @Test
    fun `the menu builds with Strava not connected`() {
        StravaConfig.availableForTest = true
        val activity = buildMenu()
        val row = findByDescriptionPrefix(
            activity.findViewById(android.R.id.content), "Strava, Not connected"
        )
        assertTrue("no not-connected Strava row", row != null)
        activity.finish()
    }

    @Test
    fun `the menu builds with Strava connected, and the sheet offers DONE and DISCONNECT`() {
        StravaConfig.availableForTest = true
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
        StravaConfig.availableForTest = false
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

    // ---- the results screen's Strava row -----------------------------------------------------

    private fun testGrant() = StravaGrant(
        accessToken = "a", refreshToken = "r", expiresAtEpochS = 9_999_999_999L,
        scopes = setOf("read", "activity:write"), athleteName = "Alex G"
    )

    /** A single-round attempt whose splits already satisfy [StravaSets.from]. */
    private fun stravaAttempt(atMillis: Long) = Attempt(
        rounds = 1, reps = 0, atMillis = atMillis, durationMs = 20 * 60 * 1_000L,
        countedReps = 30,
        setSplits = listOf(
            SetSplit(Exercise.PULLUP, 1_000L, 5, 0),
            SetSplit(Exercise.PUSHUP, 1_000L, 10, 0),
            SetSplit(Exercise.SQUAT, 1_000L, 15, 0)
        ),
        profile = CindyProfile.STANDARD
    )

    /**
     * [WorkManagerTestInitHelper.initializeTestWorkManager] first: [ResultsActivity]'s Strava
     * row asks [androidx.work.WorkManager] for live updates the moment it is built, and nothing
     * auto-initialises that under Robolectric the way it does in a real app.
     */
    private fun buildResults(attempt: Attempt): android.app.Activity {
        WorkManagerTestInitHelper.initializeTestWorkManager(context())
        val intent = ResultsActivity.intent(context(), attempt, stoppedEarly = false)
        return Robolectric.buildActivity(ResultsActivity::class.java, intent).setup().get()
    }

    private fun findText(root: android.view.View, text: String): android.view.View? {
        if (root is android.widget.TextView && root.text.toString() == text) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findText(root.getChildAt(i), text)?.let { return it }
            }
        }
        return null
    }

    @Test
    fun `the results row is absent when Strava is unavailable`() {
        StravaConfig.availableForTest = false
        val activity = buildResults(stravaAttempt(101L))
        assertNull(
            "no Strava row must appear in a build with no credentials",
            findText(activity.findViewById(android.R.id.content), "Strava")
        )
        activity.finish()
    }

    @Test
    fun `the results row offers to connect when not connected`() {
        StravaConfig.availableForTest = true
        val activity = buildResults(stravaAttempt(102L))
        assertTrue(findText(activity.findViewById(android.R.id.content), "Connect to upload") != null)
        activity.finish()
    }

    @Test
    fun `the results row offers a manual upload once connected with nothing queued`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val activity = buildResults(stravaAttempt(103L))
        assertTrue(findText(activity.findViewById(android.R.id.content), "Upload") != null)
        activity.finish()
    }

    @Test
    fun `the results row says uploading while queued or processing`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val atMillis = 104L
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.PROCESSING))
        val activity = buildResults(stravaAttempt(atMillis))
        assertTrue(findText(activity.findViewById(android.R.id.content), "Uploading…") != null)
        activity.finish()
    }

    @Test
    fun `the results row links to the activity once done`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val atMillis = 105L
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.DONE, activityId = 42L))
        val activity = buildResults(stravaAttempt(atMillis))
        assertTrue(findText(activity.findViewById(android.R.id.content), "View activity ↗") != null)
        activity.finish()
    }

    @Test
    fun `the results row offers a retry once failed`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val atMillis = 106L
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.FAILED, message = "nope"))
        val activity = buildResults(stravaAttempt(atMillis))
        assertTrue(
            findText(activity.findViewById(android.R.id.content), "Couldn't upload — tap to retry") != null
        )
        activity.finish()
    }

    @Test
    fun `the results row asks to reconnect once the grant is gone`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val atMillis = 107L
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT))
        val activity = buildResults(stravaAttempt(atMillis))
        assertTrue(findText(activity.findViewById(android.R.id.content), "Reconnect to upload") != null)
        activity.finish()
    }

    @Test
    fun `the results row says an old attempt cannot be uploaded`() {
        StravaConfig.availableForTest = true
        StravaTokenStore(context()).grant = testGrant()
        val atMillis = 108L
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.UNAVAILABLE))
        val activity = buildResults(stravaAttempt(atMillis))
        assertTrue(
            findText(activity.findViewById(android.R.id.content), "Not available for this attempt") != null
        )
        activity.finish()
    }
}
