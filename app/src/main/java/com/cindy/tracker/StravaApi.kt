package com.cindy.tracker

import java.io.IOException
import org.json.JSONException
import org.json.JSONObject

/**
 * What happened to one upload, whether just posted or polled. The upload worker acts on this
 * instead of re-deriving meaning from a status code or an `error` string itself.
 */
sealed interface UploadOutcome {
    /** Strava has the file and is still working on it. Poll [uploadId] again shortly. */
    data class Processing(val uploadId: String) : UploadOutcome

    /** The activity exists. */
    data class Ready(val activityId: Long) : UploadOutcome

    /** Strava already had this file. Treat it as done — [activityId] is null only when Strava's
     *  own message did not say which activity, which still means "do not retry". */
    data class Duplicate(val activityId: Long?) : UploadOutcome

    /** Strava refused the upload for good. Retrying would not change the outcome. */
    data class Rejected(val message: String) : UploadOutcome

    /** The token was not accepted. The caller refreshes or asks the athlete to reconnect. */
    object Unauthorized : UploadOutcome

    /** Too many requests. [retryAfterS] is Strava's own `Retry-After`, when it sent one. */
    data class RateLimited(val retryAfterS: Long?) : UploadOutcome

    /** A transient failure on Strava's side or ours — worth retrying later, unlike [Rejected]. */
    data class Transient(val reason: String) : UploadOutcome
}

/**
 * The Strava upload endpoint, over [HttpTransport] and [StravaAccessToken] only — no Android
 * types, so this and `StravaApiTest` run as plain JVM code.
 *
 * [token].get() runs before anything is sent, on every call. When the athlete is not connected —
 * or the grant was revoked — it throws [StravaAuthException]. This class does not catch that: it
 * propagates to the caller and no request goes out. Reconnecting or refreshing is the upload
 * worker's job, not this one's; [UploadOutcome.Unauthorized] only covers a 401 that gets past a
 * token that looked good when it was fetched (for example, revoked moments earlier on Strava's
 * side).
 */
class StravaApi(
    private val transport: HttpTransport,
    private val token: StravaAccessToken,
    private val base: String = StravaConfig.API_BASE
) {

    /**
     * `POST $base/uploads`, multipart: `file` (named `"$externalId.json"`, `application/json`),
     * `data_type=json`, `sport_type=Crossfit` (case-sensitive — Strava's own docs say it
     * overrides whatever the file itself would suggest), `name`, `description`, `external_id`.
     */
    fun upload(json: String, name: String, description: String, externalId: String): UploadOutcome {
        val bearer = token.get()
        val body = Multipart().apply {
            file("file", "$externalId.json", "application/json", json.toByteArray(Charsets.UTF_8))
            field("data_type", "json")
            field("sport_type", "Crossfit")
            field("name", name)
            field("description", description)
            field("external_id", externalId)
        }
        return send(
            HttpRequest(
                method = "POST",
                url = "$base/uploads",
                headers = mapOf("Authorization" to "Bearer $bearer"),
                body = body.build(),
                contentType = body.contentType
            )
        )
    }

    /** `GET $base/uploads/{uploadId}`. See the classification rules on [UploadOutcome]. */
    fun status(uploadId: String): UploadOutcome {
        val bearer = token.get()
        return send(
            HttpRequest(
                method = "GET",
                url = "$base/uploads/$uploadId",
                headers = mapOf("Authorization" to "Bearer $bearer")
            )
        )
    }

    /** Where the athlete can look at the finished activity in a browser. */
    fun activityUrl(id: Long): String = "https://www.strava.com/activities/$id"

    private fun send(request: HttpRequest): UploadOutcome =
        try {
            classify(transport.execute(request))
        } catch (e: IOException) {
            // A network failure carries no Strava semantics at all — always worth retrying.
            UploadOutcome.Transient(e.message ?: e.javaClass.simpleName)
        }
}

// ---- classification --------------------------------------------------------------------------
//
// Free functions, not methods: classifying an HttpResponse needs nothing from StravaApi's own
// state, and keeping it separate makes the status-code table above easy to read start to finish.

private val DUPLICATE_OF_ACTIVITY = Regex("""duplicate of activity (\d+)""", RegexOption.IGNORE_CASE)
private val ACTIVITY_LINK = Regex("""/activities/(\d+)""")

private fun classify(response: HttpResponse): UploadOutcome {
    val code = response.code
    return when {
        code in 200..299 -> classifySuccess(response)
        code == 401 -> UploadOutcome.Unauthorized
        code == 429 -> UploadOutcome.RateLimited(header(response, "Retry-After")?.toLongOrNull())
        // The transport never follows redirects (see StravaHttp.kt), so a 3xx here means Strava
        // sent one and it was refused rather than blindly chased to a host we did not choose.
        code in 300..399 -> UploadOutcome.Rejected("Unexpected redirect (HTTP $code)")
        code in 400..499 -> UploadOutcome.Rejected(bodyMessage(response) ?: "HTTP $code")
        else -> UploadOutcome.Transient("HTTP $code")
    }
}

private fun classifySuccess(response: HttpResponse): UploadOutcome {
    val json = try {
        JSONObject(response.body)
    } catch (e: JSONException) {
        // Strava had a hiccup rendering its own response. Not our fault and not permanent.
        return UploadOutcome.Transient("Malformed response body")
    }
    return try {
        val error = json.optNullableString("error")
        if (error != null) {
            classifyError(error)
        } else {
            val activityId = json.optNullableLong("activity_id")
            if (activityId != null) UploadOutcome.Ready(activityId)
            else UploadOutcome.Processing(json.getString("id_str"))
        }
    } catch (e: JSONException) {
        UploadOutcome.Transient("Malformed response body")
    }
}

private fun classifyError(error: String): UploadOutcome {
    if (!error.contains("duplicate", ignoreCase = true)) return UploadOutcome.Rejected(error)
    val id = DUPLICATE_OF_ACTIVITY.find(error)?.groupValues?.get(1)
        ?: ACTIVITY_LINK.find(error)?.groupValues?.get(1)
    return UploadOutcome.Duplicate(id?.toLongOrNull())
}

/** Strava's general error shape carries `message`; the uploads endpoint carries `error`. Either
 *  is a fair "why" for a 4xx that is not a 401 or a 429. */
private fun bodyMessage(response: HttpResponse): String? {
    val json = try {
        JSONObject(response.body)
    } catch (e: JSONException) {
        return null
    }
    return json.optNullableString("message") ?: json.optNullableString("error")
}

/** [HttpResponse.headers] keeps whatever casing the server sent (see StravaHttp.kt), so a name
 *  match has to ignore case instead of assuming Strava capitalises it one particular way. */
private fun header(response: HttpResponse, name: String): String? =
    response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()

private fun JSONObject.optNullableString(name: String): String? =
    if (has(name) && !isNull(name)) getString(name) else null

private fun JSONObject.optNullableLong(name: String): Long? =
    if (has(name) && !isNull(name)) getLong(name) else null
