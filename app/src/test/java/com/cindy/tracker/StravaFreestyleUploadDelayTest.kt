package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A Freestyle's sets can be given another movement on the session page after STOP, and Strava is
 * sent what the record says when the worker runs. So a Freestyle's upload waits a while, and a
 * relabel made in that time reaches Strava; one made after the upload has not, and is never
 * re-uploaded, because that would make a second activity.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaFreestyleUploadDelayTest {

    private val atMillis = 1_700_000_000_000L
    private fun context(): Context = ApplicationProvider.getApplicationContext()

    @Before
    fun setUp() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context())
        StravaConfig.availableForTest = true
        StravaUploads.clear(context())
        StravaTokenStore(context()).apply {
            grant = StravaGrant("tok", "ref", System.currentTimeMillis() / 1000 + 3_600L,
                setOf("read", "activity:write"), "Alex")
            autoUpload = true
        }
    }

    @After
    fun tearDown() {
        StravaConfig.availableForTest = null
        StravaTokenStore(context()).clearGrant()
        StravaUploads.clear(context())
    }

    private fun workState(): WorkInfo.State =
        WorkManager.getInstance(context()).getWorkInfosForUniqueWork(StravaUploads.uniqueWorkName(atMillis))
            .get().single().state

    @Test
    fun `a Freestyle waits before it uploads and a Cindy does not`() {
        val freestyle = Attempt(rounds = 0, reps = 0, atMillis = atMillis, workoutId = Workouts.FREESTYLE_ID)
        val cindy = Attempt(rounds = 5, reps = 0, atMillis = atMillis)
        assertEquals(0L, StravaUploads.uploadDelayMs(cindy))
        assertNotEquals(0L, StravaUploads.uploadDelayMs(freestyle))
    }

    @Test
    fun `an upload with a delay does not run until the delay is over`() {
        StravaUploads.onAttemptSaved(context(), atMillis, delayMs = 60_000L)
        val request = WorkManager.getInstance(context()).getWorkInfosForUniqueWork(StravaUploads.uniqueWorkName(atMillis)).get().single()
        val driver = WorkManagerTestInitHelper.getTestDriver(context())!!
        driver.setAllConstraintsMet(request.id)
        assertEquals("still waiting out its delay", WorkInfo.State.ENQUEUED, workState())
        driver.setInitialDelayMet(request.id)
        assertNotEquals("runs once the delay has passed", WorkInfo.State.ENQUEUED, workState())
    }
}
