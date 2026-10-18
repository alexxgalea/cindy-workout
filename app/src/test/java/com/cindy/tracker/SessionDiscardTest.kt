package com.cindy.tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Discarding one session takes everything filed under it and nothing filed under another.
 *
 * A session is not one record: beside the attempt sit a heart-rate trace, the time of every rep
 * and a Strava ledger entry with its queued upload, all keyed by the same `atMillis`. These tests
 * hold that the one call removes the lot, so a screen never has to remember how many places a
 * session lives in.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SessionDiscardTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val gone = 1_000L
    private val kept = 2_000L

    private val trace = HeartRateTrace(1_000L, listOf(HeartRateSample(0L, 120)), emptyList())
    private val marks = listOf(RepMark(0L, Exercise.PUSHUP, manual = false))

    @Before
    fun twoSessionsFiledEverywhere() {
        // WorkManager is started here the way the app's manifest does at launch.
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        reset()
        // A unit-test build has no Strava credentials, so the upload is only reachable through
        // the seam. After reset(), which puts the seam back.
        StravaConfig.availableForTest = true
        for (at in listOf(gone, kept)) {
            assertTrue(RecordStore(context).add(Attempt(rounds = 10, reps = 0, atMillis = at)))
            HeartRateStore(context).save(at, trace)
            RepTimesStore(context).save(at, marks)
            StravaUploads.enqueue(context, at)
        }
    }

    @After
    fun reset() {
        RecordStore(context).clear()
        HeartRateStore(context).clear()
        RepTimesStore(context).clear()
        StravaUploads.clear(context)
        StravaConfig.availableForTest = null
    }

    private fun workState(atMillis: Long): WorkInfo.State =
        WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(StravaUploads.uniqueWorkName(atMillis))
            .get().single().state

    @Test
    fun `it removes the record and the files beside it, and only that session's`() {
        assertTrue(SessionDiscard.discard(context, gone))

        assertEquals(listOf(kept), RecordStore(context).all().map { it.atMillis })
        assertNull(HeartRateStore(context).load(gone))
        assertNull(RepTimesStore(context).load(gone))
        assertEquals(trace, HeartRateStore(context).load(kept))
        assertEquals(marks, RepTimesStore(context).load(kept))
    }

    @Test
    fun `it cancels the queued Strava upload and forgets the ledger entry`() {
        assertEquals(WorkInfo.State.ENQUEUED, workState(gone))

        SessionDiscard.discard(context, gone)

        assertEquals(WorkInfo.State.CANCELLED, workState(gone))
        assertNull(StravaUploads.status(context, gone))
        assertEquals(WorkInfo.State.ENQUEUED, workState(kept))
        assertNotNull(StravaUploads.status(context, kept))
    }

    @Test
    fun `it says it removed nothing for a session that was never saved`() {
        assertFalse(SessionDiscard.discard(context, 9_999L))

        assertEquals(listOf(gone, kept), RecordStore(context).all().map { it.atMillis })
    }
}
