package com.cindy.tracker

import java.io.IOException

/**
 * A scripted [HttpTransport] for tests: queue up what [execute] should return (or throw) next,
 * then assert on what was actually sent.
 *
 * This is the one test double for every phase after S0 — S2's OAuth exchange/refresh/revoke,
 * S3's upload/poll classification, and S4's worker all script a sequence of responses here and
 * read [requests] back to check the exact method, url, headers and body that went out, rather
 * than any of them wrapping `HttpsURLConnection` a second time just to fake it.
 *
 * ```
 * val transport = FakeTransport()
 * transport.enqueue(HttpResponse(200, emptyMap(), """{"access_token":"abc"}"""))
 * transport.enqueueFailure(IOException("no network"))
 *
 * val api = StravaApi(transport, token)
 * ...
 * assertEquals("POST", transport.requests.single().method)
 * ```
 *
 * An [execute] call with nothing left in the script throws [IllegalStateException] naming the
 * request that had nothing queued for it. That is a bug in the test, not one of the two things
 * this class exists to simulate, so it is never mistaken for a scripted [IOException].
 */
class FakeTransport : HttpTransport {

    private val script = ArrayDeque<() -> HttpResponse>()
    private val sent = mutableListOf<HttpRequest>()

    /** Every request [execute] has received so far, oldest first. */
    val requests: List<HttpRequest> get() = sent

    /** The next [execute] call returns this response. */
    fun enqueue(response: HttpResponse) {
        script.addLast { response }
    }

    /** The next [execute] call throws this instead of returning, simulating a network failure. */
    fun enqueueFailure(exception: IOException) {
        script.addLast { throw exception }
    }

    override fun execute(request: HttpRequest): HttpResponse {
        sent += request
        val next = script.removeFirstOrNull()
            ?: error("FakeTransport got ${request.method} ${request.url} with nothing scripted for it")
        return next()
    }
}
