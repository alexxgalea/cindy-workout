package com.cindy.tracker

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import javax.net.ssl.HttpsURLConnection

/**
 * One HTTP request, transport-agnostic so that every Strava call — OAuth, upload, poll — can be
 * built as plain data and either sent for real or handed to [FakeTransport] in a test.
 *
 * [body] is a raw [ByteArray], which means the generated `equals`/`hashCode` compare it by
 * reference, not by content — the usual Kotlin data-class-with-array gotcha. Nothing here relies
 * on comparing two [HttpRequest] values for equality; tests inspect the fields (and decode
 * [body] to a `String` or parse it) instead of asserting equality on the whole request.
 */
data class HttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val contentType: String? = null
)

/** One HTTP response. [body] is always text: every Strava response is JSON, never binary. */
data class HttpResponse(
    val code: Int,
    val headers: Map<String, List<String>>,
    val body: String
)

/**
 * How a [HttpRequest] is actually sent. The real implementation is [UrlConnectionTransport];
 * [FakeTransport] (test source set) stands in for it everywhere else in the Strava test suite.
 *
 * [execute] throws [IOException] on a network failure (no connection, timeout, reset, …). An
 * HTTP error status is not a failure at this level — it comes back as an ordinary [HttpResponse]
 * with `code >= 400`, for the caller to classify (see `StravaApi.UploadOutcome` in S3).
 */
fun interface HttpTransport {
    fun execute(request: HttpRequest): HttpResponse
}

/**
 * The real [HttpTransport], over [HttpsURLConnection]. Every Strava endpoint is `https`, so the
 * cast is safe for every request this app builds.
 *
 * It never logs a header or a body: the bearer token lives in a header, and both the OAuth
 * token exchange and the athlete's activity data live in bodies. A stack trace from here must be
 * as safe to paste into a bug report as one from anywhere else in the app.
 */
class UrlConnectionTransport(
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 30_000
) : HttpTransport {

    override fun execute(request: HttpRequest): HttpResponse {
        val connection = URL(request.url).openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = request.method
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs
            // Never followed. A redirect would re-send the bearer token, or the athlete's upload,
            // to a host this code did not choose, and a POST is quietly turned into a GET on the
            // way. A 3xx comes back as an ordinary response for the caller to refuse.
            connection.instanceFollowRedirects = false
            for ((name, value) in request.headers) connection.setRequestProperty(name, value)
            request.contentType?.let { connection.setRequestProperty("Content-Type", it) }

            val body = request.body
            if (body != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }

            val code = connection.responseCode
            // >= 400 puts the body on the error stream instead of the input stream; either way
            // it is text, and the caller (not this class) decides what the text means.
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty()
            val headers = connection.headerFields.filterKeys { it != null }
                .mapKeys { it.key as String }
            return HttpResponse(code, headers, text)
        } finally {
            connection.disconnect()
        }
    }
}

/** `application/x-www-form-urlencoded` bodies, for the OAuth token endpoint. */
object FormBody {

    const val CONTENT_TYPE = "application/x-www-form-urlencoded; charset=utf-8"

    /** UTF-8, percent-encoded, `&`-joined — the encoding every OAuth form field needs. */
    fun encode(fields: List<Pair<String, String>>): ByteArray =
        fields.joinToString("&") { (name, value) -> "${encodePart(name)}=${encodePart(value)}" }
            .toByteArray(Charsets.UTF_8)

    private fun encodePart(value: String): String = URLEncoder.encode(value, "UTF-8")
}

/**
 * A `multipart/form-data` body, for the upload endpoint's `file` plus its plain fields
 * (`data_type`, `sport_type`, `name`, `description`, `external_id`).
 *
 * Usage is write-only and one-shot: add every [field] and [file], then call [build] exactly
 * once to get the finished, boundary-terminated bytes.
 */
class Multipart(private val boundary: String = "CindyStrava" + UUID.randomUUID().toString().replace("-", "")) {

    private val buffer = ByteArrayOutputStream()

    /** The request's `Content-Type` header — the boundary must match what was written. */
    val contentType: String get() = "multipart/form-data; boundary=$boundary"

    /** A plain text field, such as `data_type` or `sport_type`. */
    fun field(name: String, value: String) {
        writePartHeader(name, filename = null, contentType = null)
        writeText(value)
        writeText("\r\n")
    }

    /** A binary part — the activity JSON goes here as `file`. */
    fun file(name: String, filename: String, contentType: String, bytes: ByteArray) {
        writePartHeader(name, filename, contentType)
        buffer.write(bytes)
        writeText("\r\n")
    }

    /** The finished body. Call once, after every [field] and [file]. */
    fun build(): ByteArray {
        writeText("--$boundary--\r\n")
        return buffer.toByteArray()
    }

    private fun writePartHeader(name: String, filename: String?, contentType: String?) {
        writeText("--$boundary\r\n")
        writeText("Content-Disposition: form-data; name=\"${escape(name)}\"")
        if (filename != null) writeText("; filename=\"${escape(filename)}\"")
        writeText("\r\n")
        if (contentType != null) writeText("Content-Type: $contentType\r\n")
        writeText("\r\n")
    }

    private fun writeText(text: String) = buffer.write(text.toByteArray(Charsets.UTF_8))

    private fun escape(value: String) = value.replace("\"", "\\\"")
}

/**
 * The athlete is not connected to Strava, or Strava revoked the grant since they were.
 *
 * [revoked] tells the caller which: true means a refresh was attempted and rejected, so the
 * stored grant is already cleared and reconnecting is the only way forward; false means there
 * was never a grant to use in the first place.
 */
class StravaAuthException(
    message: String = "Not connected to Strava",
    val revoked: Boolean = false
) : Exception(message)

/**
 * The seam between OAuth (S2 implements this) and every API call (S3 only consumes it). [get]
 * returns a currently-valid bearer token, refreshing first when it was close to expiry, and
 * throws [StravaAuthException] when there is nothing to hand back.
 */
fun interface StravaAccessToken {
    fun get(): String
}
