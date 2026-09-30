package com.cindy.tracker

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.SecureRandom
import java.util.Base64
import org.json.JSONObject

/**
 * What Strava's redirect meant, once [StravaAuth.parseRedirect] has read it.
 *
 * There is no "success" case beyond [Code]: even a redirect that carries a code is not yet a
 * connection, because the athlete may have unticked the one scope the app needs. Turning that
 * into its own case ([MissingWriteScope]) rather than folding it into [Code] means the caller
 * cannot forget to check.
 */
sealed interface RedirectResult {
    /** A code worth exchanging, and the scopes Strava says were actually granted for it. */
    data class Code(val code: String, val scopes: Set<String>) : RedirectResult

    /** The athlete declined on Strava's consent page. Not an error — just not connected. */
    object Denied : RedirectResult

    /**
     * The redirect's `state` does not match the one this app minted before it opened the
     * browser — missing entirely counts as a mismatch, not a separate case. Either there is no
     * OAuth attempt in flight, or this intent was not the answer to ours: a stale entry replayed
     * from task history, or a deep link crafted by something else on the phone. It is silently
     * ignored rather than acted on.
     */
    object StateMismatch : RedirectResult

    /** The code is genuine, but the athlete unticked `activity:write` on the consent page. */
    object MissingWriteScope : RedirectResult

    /** The redirect could not be read as a URI, or carried neither a code nor an error. */
    object Malformed : RedirectResult
}

/**
 * OAuth, end to end: the URL that opens Strava's consent screen, the state that ties a redirect
 * back to the request that caused it, what a redirect meant, and the three calls against the
 * token endpoint. Everything here is pure over [HttpTransport], so [StravaAuthTest] scripts it
 * with [FakeTransport] on the plain JVM — no Robolectric needed for any of it.
 *
 * [authorizeUri], [newState] and [parseRedirect] need no network and live on the companion,
 * so a caller that only wants to build a URL or read a redirect — [MenuActivity],
 * [StravaAuthActivity] — never has to construct one of these with a transport just to reach
 * them. [exchange], [refresh] and [revoke] are the three calls that do reach the network, and are
 * instance methods for exactly that reason.
 */
class StravaAuth(private val transport: HttpTransport) {

    /**
     * `POST {API_BASE}/oauth/token`, `grant_type=authorization_code`. The one-time [code] from a
     * [RedirectResult.Code] becomes a [StravaGrant] — the athlete is connected once this returns.
     *
     * Any HTTP error throws a plain [StravaAuthException] (`revoked = false`): there is no grant
     * yet for this call to have revoked.
     */
    fun exchange(code: String): StravaGrant {
        val response = post(
            "${StravaConfig.API_BASE}/oauth/token",
            listOf(
                "client_id" to StravaConfig.clientId,
                "client_secret" to StravaConfig.clientSecret,
                "code" to code,
                "grant_type" to "authorization_code"
            )
        )
        if (response.code >= 400) {
            throw StravaAuthException("Strava could not exchange the code (${response.code})")
        }
        return parseGrant(response.body)
    }

    /**
     * `POST {API_BASE}/oauth/token`, `grant_type=refresh_token`. Strava rotates the refresh
     * token on every call, and the old one stops working the moment the new one is issued —
     * [StravaSession] persists what comes back before it uses the access token inside it.
     *
     * A 400 or 401 means the grant itself is gone — revoked from strava.com, or the athlete
     * disconnected from a different device — so this throws `StravaAuthException(revoked = true)`
     * rather than the plain form [exchange] throws. [StravaSession] is the one that actually
     * clears the stored grant; this class never touches [StravaTokenStore].
     */
    fun refresh(refreshToken: String): StravaGrant {
        val response = post(
            "${StravaConfig.API_BASE}/oauth/token",
            listOf(
                "client_id" to StravaConfig.clientId,
                "client_secret" to StravaConfig.clientSecret,
                "refresh_token" to refreshToken,
                "grant_type" to "refresh_token"
            )
        )
        if (response.code == 400 || response.code == 401) {
            throw StravaAuthException("Strava rejected the refresh token", revoked = true)
        }
        if (response.code >= 400) {
            throw StravaAuthException("Strava could not refresh the token (${response.code})")
        }
        return parseGrant(response.body)
    }

    /**
     * `POST {OAUTH_BASE}/revoke`, Basic-authenticated with the app's own credentials rather than
     * the athlete's token. [tokenTypeHint] is `"access_token"` or `"refresh_token"`, naming which
     * of the two [token] is; Strava revokes the whole grant either way.
     *
     * Callers treat this as best-effort — see [MenuActivity]'s DISCONNECT, which clears the local
     * grant even when this throws, because an athlete who is offline or has already removed the
     * app from strava.com must not be stuck looking connected.
     */
    fun revoke(token: String, tokenTypeHint: String) {
        val credentials = "${StravaConfig.clientId}:${StravaConfig.clientSecret}"
        val basic = Base64.getEncoder().encodeToString(credentials.toByteArray(Charsets.UTF_8))
        val response = transport.execute(
            HttpRequest(
                method = "POST",
                url = "${StravaConfig.OAUTH_BASE}/revoke",
                headers = mapOf("Authorization" to "Basic $basic"),
                body = FormBody.encode(listOf("token" to token, "token_type_hint" to tokenTypeHint)),
                contentType = FormBody.CONTENT_TYPE
            )
        )
        if (response.code >= 400) {
            throw StravaAuthException("Strava could not revoke the grant (${response.code})")
        }
    }

    private fun post(url: String, fields: List<Pair<String, String>>) =
        transport.execute(
            HttpRequest(
                method = "POST",
                url = url,
                body = FormBody.encode(fields),
                contentType = FormBody.CONTENT_TYPE
            )
        )

    /**
     * Reads the token endpoint's response. `scope` is documented as space-delimited since
     * 2026-04-23, but this splits on both spaces and commas — cheap insurance against an older
     * or reverted API build, and the same tolerance [parseRedirect] applies to the redirect's own
     * `scope` parameter.
     */
    private fun parseGrant(body: String): StravaGrant {
        val json = JSONObject(body)
        val athlete = json.optJSONObject("athlete")
        val athleteName = athlete?.let {
            listOfNotNull(
                it.optString("firstname").takeIf(String::isNotBlank),
                it.optString("lastname").takeIf(String::isNotBlank)
            ).joinToString(" ").takeIf(String::isNotBlank)
        }
        return StravaGrant(
            accessToken = json.getString("access_token"),
            refreshToken = json.getString("refresh_token"),
            expiresAtEpochS = json.getLong("expires_at"),
            scopes = splitScopes(json.optString("scope", "")),
            athleteName = athleteName
        )
    }

    companion object {

        /** 128 random bits, hex-encoded — long enough that guessing one is not a real attack. */
        fun newState(): String {
            val bytes = ByteArray(16)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }

        /**
         * Strava's mobile authorize URL: `Intent.ACTION_VIEW` on this opens the Strava app when
         * it is installed, and mobile web otherwise — [MenuActivity] does not need to know which.
         *
         * `approval_prompt=auto` skips a re-consent screen for an athlete who already granted
         * this app access and only disconnected on our side.
         */
        fun authorizeUri(state: String): String {
            val params = listOf(
                "client_id" to StravaConfig.clientId,
                "redirect_uri" to StravaConfig.REDIRECT_URI,
                "response_type" to "code",
                "approval_prompt" to "auto",
                "scope" to StravaConfig.SCOPE,
                "state" to state
            )
            val query = params.joinToString("&") { (name, value) -> "$name=${encode(value)}" }
            return "${StravaConfig.OAUTH_BASE}/mobile/authorize?$query"
        }

        /**
         * What a redirect to [StravaConfig.REDIRECT_URI] meant. [expectedState] is the value
         * [StravaTokenStore.pendingState] held when the athlete left for Strava's consent page.
         *
         * The state check runs before anything else, including before noticing `error=`: a denial
         * for someone else's request is not this app's business to report either.
         */
        fun parseRedirect(uri: String, expectedState: String): RedirectResult {
            val query = try {
                URI(uri).rawQuery
            } catch (e: Exception) {
                null
            } ?: return RedirectResult.Malformed

            val params = parseQuery(query)
            if (params["state"] != expectedState) return RedirectResult.StateMismatch
            if (params["error"] != null) return RedirectResult.Denied

            val code = params["code"] ?: return RedirectResult.Malformed
            val scopes = splitScopes(params["scope"].orEmpty())
            if (!scopes.contains("activity:write")) return RedirectResult.MissingWriteScope
            return RedirectResult.Code(code, scopes)
        }

        /** Strava documents the token endpoint's `scope` as space-delimited; the redirect's own
         *  `scope` parameter was comma-delimited before that. Accepting both costs nothing. */
        private fun splitScopes(raw: String): Set<String> =
            raw.split(",", " ").map(String::trim).filter(String::isNotEmpty).toSet()

        private fun parseQuery(query: String): Map<String, String> =
            query.split("&").mapNotNull { pair ->
                val i = pair.indexOf('=')
                if (i < 0) null else {
                    val key = URLDecoder.decode(pair.substring(0, i), "UTF-8")
                    val value = URLDecoder.decode(pair.substring(i + 1), "UTF-8")
                    key to value
                }
            }.toMap()

        private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
    }
}
