package com.cindy.tracker

import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker.Result
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The upload worker's own decisions, over [FakeTransport] and [TestListenableWorkerBuilder] — no
 * real network and no real waiting between polls.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StravaUploadWorkerTest {

    private val atMillis = 1_700_000_000_000L

    private fun context() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Before
    fun setUp() {
        StravaTokenStore(context()).clearGrant()
        RecordStore(context()).clear()
        StravaUploads.clear(context())
        HeartRateStore(context()).clear()
    }

    @After
    fun tearDown() {
        StravaServices.transport = { UrlConnectionTransport() }
        StravaServices.sleep = { kotlinx.coroutines.delay(it) }
        StravaTokenStore(context()).clearGrant()
        RecordStore(context()).clear()
        StravaUploads.clear(context())
        HeartRateStore(context()).clear()
    }

    private fun connect(expiresInS: Long = 3_600L) {
        StravaTokenStore(context()).grant = StravaGrant(
            accessToken = "tok", refreshToken = "ref",
            expiresAtEpochS = System.currentTimeMillis() / 1000 + expiresInS,
            scopes = setOf("read", "activity:write"), athleteName = "Alex"
        )
    }

    /** A refresh response StravaAuth can parse, far enough out to not need a second refresh. */
    private fun refreshResponse(accessToken: String) = HttpResponse(
        200, emptyMap(),
        """{"access_token":"$accessToken","refresh_token":"r2",""" +
            """"expires_at":${System.currentTimeMillis() / 1000 + 3_600},"scope":"read,activity:write"}"""
    )

    /** A valid, single-round attempt whose splits already satisfy [StravaSets.from]. */
    private fun saveValidAttempt(at: Long = atMillis): Attempt {
        val splits = listOf(
            SetSplit(Exercise.PULLUP, 1_000L, 5, 0),
            SetSplit(Exercise.PUSHUP, 1_000L, 10, 0),
            SetSplit(Exercise.SQUAT, 1_000L, 15, 0)
        )
        val attempt = Attempt(
            rounds = 1, reps = 0, atMillis = at, durationMs = 20 * 60 * 1_000L,
            countedReps = 30, setSplits = splits, profile = CindyProfile.STANDARD
        )
        RecordStore(context()).add(attempt)
        return attempt
    }

    private fun useTransport(transport: FakeTransport) {
        StravaServices.transport = { transport }
        StravaServices.sleep = {} // no real waiting between polls in a test
    }

    private fun runWorker(at: Long = atMillis): Result =
        TestListenableWorkerBuilder<StravaUploadWorker>(
            context(), workDataOf(StravaUploadWorker.KEY_AT_MILLIS to at)
        ).build().startWork().get()

    /** Enough of a body for [Calories.estimate] to use a saved trace instead of falling back. */
    private fun saveBody() {
        val profile = Profile(context())
        profile.bodyWeightKg = 70.0
        profile.birthYear = 1990
        profile.sex = Sex.MALE
    }

    private fun boundaryOf(request: HttpRequest): String =
        Regex("boundary=(.+)").find(request.contentType!!)!!.groupValues[1]

    /** The value of one simple (non-file) multipart field, e.g. "description". */
    private fun fieldPart(request: HttpRequest, name: String): String {
        val body = String(request.body!!, Charsets.UTF_8)
        val marker = "Content-Disposition: form-data; name=\"$name\"\r\n\r\n"
        val start = body.indexOf(marker) + marker.length
        val end = body.indexOf("\r\n--${boundaryOf(request)}", start)
        return body.substring(start, end)
    }

    /** Parses the "file" part's own body as the JSON payload it is. */
    private fun payloadOf(request: HttpRequest): JSONObject {
        val body = String(request.body!!, Charsets.UTF_8)
        val marker = "Content-Type: application/json\r\n\r\n"
        val start = body.indexOf(marker) + marker.length
        val end = body.indexOf("\r\n--${boundaryOf(request)}", start)
        return JSONObject(body.substring(start, end))
    }

    // ---- gates before any network call -----------------------------------------------------

    @Test
    fun `not connected asks to reconnect instead of spinning`() {
        saveValidAttempt()
        assertEquals(Result.success(), runWorker())
        assertEquals(StravaUploadState.NEEDS_RECONNECT, StravaUploads.status(context(), atMillis)?.state)
    }

    @Test
    fun `an attempt no longer on record is unavailable`() {
        connect()
        assertEquals(Result.success(), runWorker())
        assertEquals(StravaUploadState.UNAVAILABLE, StravaUploads.status(context(), atMillis)?.state)
    }

    @Test
    fun `a set list that disagrees with the total is unavailable, not guessed at`() {
        connect()
        val splits = listOf(
            SetSplit(Exercise.PULLUP, 1_000L, 5, 0),
            SetSplit(Exercise.PUSHUP, 1_000L, 10, 0),
            SetSplit(Exercise.SQUAT, 1_000L, 15, 0)
        )
        // countedReps disagrees with both the banked sets (30) and a plausible movement in
        // progress: exactly the sum-mismatch StravaSets.from refuses rather than guesses past.
        val attempt = Attempt(
            rounds = 1, reps = 0, atMillis = atMillis, durationMs = 20 * 60 * 1_000L,
            countedReps = 999, setSplits = splits, profile = CindyProfile.STANDARD
        )
        RecordStore(context()).add(attempt)

        assertEquals(Result.success(), runWorker())
        assertEquals(StravaUploadState.UNAVAILABLE, StravaUploads.status(context(), atMillis)?.state)
    }

    // ---- the happy path and its polling ------------------------------------------------------

    @Test
    fun `the happy path posts once, polls once, and ends done`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":42}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.DONE, status?.state)
        assertEquals(42L, status?.activityId)
        assertEquals(1, transport.requests.count { it.method == "POST" })
        assertEquals(1, transport.requests.count { it.method == "GET" })
    }

    // ---- a saved heart-rate trace -------------------------------------------------------------

    @Test
    fun `a saved heart-rate trace rides along as a stream, and the description says so`() {
        connect()
        saveBody()
        val attempt = saveValidAttempt()
        val traceStart = attempt.atMillis - attempt.durationMs - 2_000L
        val trace = HeartRateTrace(
            startedAtMillis = traceStart,
            // Every 5 s, exactly Calories.MAX_HOLD_MS, covers the whole clock with no gap.
            samples = (0L until attempt.durationMs step 5_000L).map { HeartRateSample(it, 150) },
            pauses = emptyList()
        )
        HeartRateStore(context()).save(atMillis, trace)
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":42}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        val post = transport.requests.first { it.method == "POST" }
        val payload = payloadOf(post)
        assertEquals(
            java.time.Instant.ofEpochMilli(traceStart).truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString(),
            payload.getString("start_time")
        )
        val streams = payload.getJSONObject("streams")
        val time = streams.getJSONArray("time")
        val heartrate = streams.getJSONArray("heartrate")
        assertTrue(time.length() > 0)
        assertEquals(time.length(), heartrate.length())
        assertTrue(fieldPart(post, "description").contains("Calories estimated from heart rate"))
    }

    @Test
    fun `without a saved trace the upload is unchanged, carrying no heart-rate stream`() {
        connect()
        saveBody()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":42}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        val post = transport.requests.first { it.method == "POST" }
        assertFalse(payloadOf(post).has("streams"))
        assertTrue(fieldPart(post, "description").contains("Calories estimated from body weight"))
    }

    @Test
    fun `polling more than once in one run still posts only once`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":91}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        assertEquals(1, transport.requests.count { it.method == "POST" })
        assertEquals(2, transport.requests.count { it.method == "GET" })
        assertEquals(StravaUploadState.DONE, StravaUploads.status(context(), atMillis)?.state)
    }

    @Test
    fun `a poll that never finishes retries instead of waiting forever`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        repeat(10) {
            transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))
        }
        useTransport(transport)

        assertEquals(Result.retry(), runWorker())
        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.PROCESSING, status?.state)
        assertEquals("555", status?.uploadId)
    }

    // ---- resuming after a process death ------------------------------------------------------

    @Test
    fun `a resumed worker polls instead of posting again`() {
        connect()
        saveValidAttempt()
        // As if a previous run already had this accepted and died before it finished polling.
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.PROCESSING, uploadId = "555"))
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":77}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        assertTrue("must never re-POST a file Strava already has", transport.requests.none { it.method == "POST" })
        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.DONE, status?.state)
        assertEquals(77L, status?.activityId)
    }

    @Test
    fun `queuing again while Strava is still processing keeps the upload id, so nothing is resent`() {
        connect()
        saveValidAttempt()
        StravaUploads.write(context(), atMillis, StravaUploadStatus(StravaUploadState.PROCESSING, uploadId = "555"))
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context())

        StravaUploads.enqueue(context(), atMillis)

        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.QUEUED, status?.state)
        assertEquals("555", status?.uploadId)
    }

    // ---- outcomes other than a clean Ready ---------------------------------------------------

    @Test
    fun `a duplicate upload is treated as done`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(201, emptyMap(), """{"error":"cindy-$atMillis.json duplicate of activity 42"}""")
        )
        useTransport(transport)

        assertEquals(Result.success(), runWorker())
        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.DONE, status?.state)
        assertEquals(42L, status?.activityId)
    }

    @Test
    fun `a rejected upload fails without asking to retry`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(400, emptyMap(), """{"message":"invalid sport_type"}"""))
        useTransport(transport)

        assertEquals(Result.failure(), runWorker())
        val status = StravaUploads.status(context(), atMillis)
        assertEquals(StravaUploadState.FAILED, status?.state)
        assertEquals("invalid sport_type", status?.message)
    }

    @Test
    fun `a 401 refreshes once and finishes the upload with the new token`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        transport.enqueue(refreshResponse("freshA"))
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"9","error":null,"activity_id":100}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())

        assertEquals(StravaUploadState.DONE, StravaUploads.status(context(), atMillis)?.state)
        assertEquals("freshA", StravaTokenStore(context()).grant?.accessToken)
        // upload, refresh, retried upload — never a second refresh, never a third upload.
        assertEquals(3, transport.requests.size)
    }

    @Test
    fun `a 401 that survives a refresh asks to reconnect`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        transport.enqueue(refreshResponse("freshA"))
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        useTransport(transport)

        assertEquals(Result.success(), runWorker())
        assertEquals(StravaUploadState.NEEDS_RECONNECT, StravaUploads.status(context(), atMillis)?.state)
    }

    @Test
    fun `a 401 whose own refresh is rejected asks to reconnect without a second upload`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}"""))
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Unauthorized"}""")) // the refresh itself
        useTransport(transport)

        assertEquals(Result.success(), runWorker())
        assertEquals(StravaUploadState.NEEDS_RECONNECT, StravaUploads.status(context(), atMillis)?.state)
        assertNull("a refresh Strava rejects must clear the grant", StravaTokenStore(context()).grant)
        assertEquals(2, transport.requests.size)
    }

    @Test
    fun `a 5xx is worth retrying`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(503, emptyMap(), "oops"))
        useTransport(transport)

        assertEquals(Result.retry(), runWorker())
    }

    @Test
    fun `rate limiting is worth retrying`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(429, mapOf("Retry-After" to listOf("30")), ""))
        useTransport(transport)

        assertEquals(Result.retry(), runWorker())
    }

    @Test
    fun `a network failure is worth retrying`() {
        connect()
        saveValidAttempt()
        val transport = FakeTransport()
        transport.enqueueFailure(java.io.IOException("no network"))
        useTransport(transport)

        assertEquals(Result.retry(), runWorker())
    }
}
