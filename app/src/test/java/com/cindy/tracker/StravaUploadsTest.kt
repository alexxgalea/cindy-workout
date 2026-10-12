package com.cindy.tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The ledger's own codec — pure, so it needs no [android.content.Context] to test. */
class StravaUploadsTest {

    @Test
    fun `a queued entry round-trips with nothing else set`() {
        val status = StravaUploadStatus(StravaUploadState.QUEUED)
        assertEquals(status, StravaUploads.decode(StravaUploads.encode(status)))
    }

    @Test
    fun `every field round-trips once it is known`() {
        val status = StravaUploadStatus(
            StravaUploadState.DONE, uploadId = "12345", activityId = 987654321L, message = null
        )
        assertEquals(status, StravaUploads.decode(StravaUploads.encode(status)))
    }

    @Test
    fun `a failed entry keeps its message`() {
        val status = StravaUploadStatus(StravaUploadState.FAILED, message = "duplicate of nothing sensible")
        assertEquals(status, StravaUploads.decode(StravaUploads.encode(status)))
    }

    @Test
    fun `every state round-trips`() {
        StravaUploadState.entries.forEach { state ->
            val status = StravaUploadStatus(state)
            assertEquals(status, StravaUploads.decode(StravaUploads.encode(status)))
        }
    }

    @Test
    fun `null decodes to null`() {
        assertNull(StravaUploads.decode(null))
    }

    @Test
    fun `garbage decodes to null rather than guessing`() {
        assertNull(StravaUploads.decode("not the format at all"))
        assertNull(StravaUploads.decode("QUEUED|only|two"))
    }

    @Test
    fun `an unknown state name decodes to null`() {
        assertNull(StravaUploads.decode("SOMETHING_NEWER||||"))
    }

    @Test
    fun `an upload has reached Strava once it is done or Strava has accepted the file`() {
        val reached = listOf(
            StravaUploadStatus(StravaUploadState.DONE, activityId = 5L),
            StravaUploadStatus(StravaUploadState.PROCESSING, uploadId = "u"),
            // Accepted on an earlier run and waiting to be polled: Strava has the file.
            StravaUploadStatus(StravaUploadState.QUEUED, uploadId = "u"),
            StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT, uploadId = "u")
        )
        val notReached = listOf(
            StravaUploadStatus(StravaUploadState.QUEUED),
            StravaUploadStatus(StravaUploadState.NEEDS_RECONNECT),
            StravaUploadStatus(StravaUploadState.UNAVAILABLE),
            StravaUploadStatus(StravaUploadState.FAILED, message = "rejected"),
            // Strava took the file and then refused it: there is no activity to leave behind.
            StravaUploadStatus(StravaUploadState.FAILED, uploadId = "u", message = "unreadable")
        )
        reached.forEach { assertEquals("$it", true, it.reachedStrava) }
        notReached.forEach { assertEquals("$it", false, it.reachedStrava) }
    }
}
