package com.cindy.tracker

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class StravaApiTest {

    private fun tokenOf(value: String): StravaAccessToken = StravaAccessToken { value }

    // ---- status: request shape ----------------------------------------------------------------

    @Test
    fun `status polls the upload by id with the bearer header`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"555","error":null,"activity_id":null}"""))

        StravaApi(transport, tokenOf("secret-token")).status("555")

        val request = transport.requests.single()
        assertEquals("GET", request.method)
        assertEquals("https://www.strava.com/api/v3/uploads/555", request.url)
        assertEquals("Bearer secret-token", request.headers["Authorization"])
    }

    // ---- classification: success ---------------------------------------------------------------

    @Test
    fun `no error and no activity id means still processing, keyed by the 64-bit id_str`() {
        val bigId = "12345678901234567" // outside Int range, and precise only as a string
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(200, emptyMap(), """{"id":$bigId,"id_str":"$bigId","error":null,"activity_id":null}""")
        )

        val outcome = StravaApi(transport, tokenOf("t")).status(bigId)

        assertEquals(UploadOutcome.Processing(bigId), outcome)
    }

    @Test
    fun `a 201 with no activity id is processing too`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(201, emptyMap(), """{"id_str":"1","error":null,"activity_id":null}"""))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Processing("1"), outcome)
    }

    @Test
    fun `an activity id means the upload is ready`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), """{"id_str":"1","error":null,"activity_id":21234316}"""))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Ready(21234316L), outcome)
    }

    // ---- classification: duplicate ------------------------------------------------------------

    @Test
    fun `a duplicate error names the existing activity`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(200, emptyMap(), """{"id_str":"1","error":"club.gpx duplicate of activity 21234316","activity_id":null}""")
        )

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Duplicate(21234316L), outcome)
    }

    @Test
    fun `a duplicate error given as an html link still yields the activity id`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(200, emptyMap(), """{"id_str":"1","error":"Duplicate of <a href='/activities/123'>this activity</a>","activity_id":null}""")
        )

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Duplicate(123L), outcome)
    }

    @Test
    fun `a duplicate error with no parsable id is still a duplicate, not a rejection`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(200, emptyMap(), """{"id_str":"1","error":"This file is a duplicate of a previous upload","activity_id":null}""")
        )

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Duplicate(null), outcome)
    }

    // ---- classification: rejected, unauthorized, rate-limited -----------------------------------

    @Test
    fun `a non-duplicate error rejects with strava's own message`() {
        val transport = FakeTransport()
        transport.enqueue(
            HttpResponse(200, emptyMap(), """{"id_str":"1","error":"There was an error processing your activity.","activity_id":null}""")
        )

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Rejected("There was an error processing your activity."), outcome)
    }

    @Test
    fun `401 is unauthorized, not a permanent rejection`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(401, emptyMap(), """{"message":"Authorization Error"}"""))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Unauthorized, outcome)
    }

    @Test
    fun `429 reads Retry-After even when the header name's casing differs`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(429, mapOf("retry-after" to listOf("120")), "{}"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.RateLimited(120L), outcome)
    }

    @Test
    fun `429 also reads a fully upper-cased Retry-After header`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(429, mapOf("RETRY-AFTER" to listOf("30")), "{}"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.RateLimited(30L), outcome)
    }

    @Test
    fun `429 with no Retry-After header still rate-limits, with no known wait`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(429, emptyMap(), "{}"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.RateLimited(null), outcome)
    }

    @Test
    fun `a 404 rejects using the body's own message`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(404, emptyMap(), """{"message":"Record Not Found"}"""))

        val outcome = StravaApi(transport, tokenOf("t")).status("999")

        assertEquals(UploadOutcome.Rejected("Record Not Found"), outcome)
    }

    @Test
    fun `a 4xx with no usable body message falls back to the http code`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(403, emptyMap(), "not json"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Rejected("HTTP 403"), outcome)
    }

    // ---- classification: redirects, server errors, transport failures, malformed bodies ---------

    @Test
    fun `a redirect is refused rather than silently chased or mistaken for something else`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(302, mapOf("Location" to listOf("https://example.invalid")), ""))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertEquals(UploadOutcome.Rejected("Unexpected redirect (HTTP 302)"), outcome)
    }

    @Test
    fun `a 5xx is transient, worth retrying later`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(503, emptyMap(), "Service Unavailable"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertTrue(outcome is UploadOutcome.Transient)
    }

    @Test
    fun `an IOException from the transport is transient`() {
        val transport = FakeTransport()
        transport.enqueueFailure(IOException("no network"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertTrue(outcome is UploadOutcome.Transient)
    }

    @Test
    fun `a malformed 2xx body is transient, not a permanent rejection`() {
        val transport = FakeTransport()
        transport.enqueue(HttpResponse(200, emptyMap(), "not valid json {"))

        val outcome = StravaApi(transport, tokenOf("t")).status("1")

        assertTrue(outcome is UploadOutcome.Transient)
    }

    // ---- the token seam --------------------------------------------------------------------------

    @Test
    fun `a revoked token propagates, and no request is sent`() {
        val transport = FakeTransport()
        val revoked = StravaAccessToken { throw StravaAuthException(revoked = true) }

        try {
            StravaApi(transport, revoked).status("1")
            fail("expected StravaAuthException")
        } catch (e: StravaAuthException) {
            assertTrue(e.revoked)
        }
        assertTrue(transport.requests.isEmpty())
    }
}
