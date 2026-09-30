package com.cindy.tracker

import android.content.Context

/**
 * One connected grant: the tokens, when the access token expires, the scopes Strava actually
 * gave, and the athlete's name for the menu row and the "Connected to Strava as …" toast.
 *
 * [expiresAtEpochS] is epoch **seconds**, matching Strava's own `expires_at` field, not the
 * millisecond epoch the rest of the app uses for `atMillis` — converting at the one place that
 * reads it ([StravaSession]) is cheaper than a wrong unit compiling silently everywhere else.
 */
data class StravaGrant(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtEpochS: Long,
    val scopes: Set<String>,
    val athleteName: String?
)

/**
 * Everything about the athlete's Strava connection that has to survive the app closing: the
 * grant itself, the OAuth attempt in flight, and the two settings S4 reads.
 *
 * Its own prefs file, `strava` — never `cindy`, the one [Profile] uses — because
 * `backup_rules.xml` and `data_extraction_rules.xml` exclude `strava.xml` by name from every
 * kind of backup. A token living in the same file as body weight would mean excluding body
 * weight too, or not excluding anything.
 */
class StravaTokenStore(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * The current grant, or null when there isn't one. Setting it to null is how a grant is
     * forgotten — see [clearGrant].
     *
     * Writes use `commit()`, not `apply()`. Strava rotates the refresh token on every refresh and
     * invalidates the old one immediately, so the moment [StravaSession] hands out the new access
     * token, the refresh token that can renew it again must already be on disk — `apply()` only
     * promises that "eventually," which is not a promise a process that dies right after can
     * collect on.
     */
    var grant: StravaGrant?
        get() {
            val accessToken = prefs.getString(KEY_ACCESS_TOKEN, null) ?: return null
            val refreshToken = prefs.getString(KEY_REFRESH_TOKEN, null) ?: return null
            return StravaGrant(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresAtEpochS = prefs.getLong(KEY_EXPIRES_AT, 0L),
                scopes = prefs.getString(KEY_SCOPES, "").orEmpty()
                    .split(",").filter(String::isNotEmpty).toSet(),
                athleteName = prefs.getString(KEY_ATHLETE_NAME, null)
            )
        }
        set(value) {
            val edit = prefs.edit()
            if (value == null) {
                edit.remove(KEY_ACCESS_TOKEN).remove(KEY_REFRESH_TOKEN).remove(KEY_EXPIRES_AT)
                    .remove(KEY_SCOPES).remove(KEY_ATHLETE_NAME)
            } else {
                edit.putString(KEY_ACCESS_TOKEN, value.accessToken)
                    .putString(KEY_REFRESH_TOKEN, value.refreshToken)
                    .putLong(KEY_EXPIRES_AT, value.expiresAtEpochS)
                    .putString(KEY_SCOPES, value.scopes.joinToString(","))
                    .putString(KEY_ATHLETE_NAME, value.athleteName)
            }
            edit.commit()
        }

    /** Whether there is a grant to upload with. Read by S4 before it enqueues any work. */
    val connected: Boolean get() = grant != null

    /** Forgets the grant. Used on DISCONNECT and when a refresh comes back revoked. */
    fun clearGrant() {
        grant = null
    }

    /**
     * The `state` [MenuActivity] minted right before it opened Strava's consent page, so
     * [StravaAuthActivity] can tell a genuine redirect from anything else that might land on
     * the same scheme. Null once there is no attempt in flight — see [StravaAuth.parseRedirect].
     */
    var pendingState: String?
        get() = prefs.getString(KEY_PENDING_STATE, null)
        set(value) = editString(KEY_PENDING_STATE, value)

    /**
     * Set when the athlete asked to connect *in order to* upload one particular attempt — from
     * the results screen, in S4 — rather than from the menu on its own. [StravaAuthActivity]
     * enqueues this attempt once connected, then clears it.
     */
    var afterConnectUploadAtMillis: Long?
        get() = prefs.getLong(KEY_AFTER_CONNECT, NO_MILLIS).takeIf { it != NO_MILLIS }
        set(value) {
            val edit = prefs.edit()
            if (value == null) edit.remove(KEY_AFTER_CONNECT) else edit.putLong(KEY_AFTER_CONNECT, value)
            edit.apply()
        }

    /** Whether a saved attempt uploads on its own. On by default once connected; S4's toggle. */
    var autoUpload: Boolean
        get() = prefs.getBoolean(KEY_AUTO_UPLOAD, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_UPLOAD, value).apply()

    private fun editString(key: String, value: String?) {
        val edit = prefs.edit()
        if (value == null) edit.remove(key) else edit.putString(key, value)
        edit.apply()
    }

    companion object {
        const val PREFS_NAME = "strava"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val KEY_SCOPES = "scopes"
        private const val KEY_ATHLETE_NAME = "athlete_name"
        private const val KEY_PENDING_STATE = "pending_state"
        private const val KEY_AFTER_CONNECT = "after_connect_upload_at_millis"
        private const val KEY_AUTO_UPLOAD = "auto_upload"
        /** `atMillis` is always a positive epoch millisecond, so this is a safe "unset" marker. */
        private const val NO_MILLIS = -1L
    }
}

/**
 * The live [StravaAccessToken]: reads the stored grant, refreshes it when it is close to expiry,
 * persists the refreshed grant before handing out the access token inside it, and clears the
 * grant when Strava says it is no longer good for anything.
 *
 * [clock] returns epoch milliseconds and defaults to [System.currentTimeMillis]; tests inject one
 * that does not actually wait six hours to reach the refresh window.
 *
 * [get] is `synchronized` on a lock shared by every instance in the process, not one per
 * [StravaTokenStore]. Two upload workers racing to refresh at the same moment would each rotate
 * the refresh token Strava just handed the other one, so the loser's own refresh — started before
 * it could see the winner's write — would persist a token Strava has already invalidated. The
 * lock serialises them: the loser waits, then rereads a grant that is already fresh and returns
 * it without refreshing a second time.
 */
class StravaSession(
    private val store: StravaTokenStore,
    private val auth: StravaAuth,
    private val clock: () -> Long = System::currentTimeMillis
) : StravaAccessToken {

    override fun get(): String = synchronized(LOCK) {
        val grant = store.grant ?: throw StravaAuthException()
        val secondsLeft = grant.expiresAtEpochS - clock() / 1000L
        if (secondsLeft >= REFRESH_WINDOW_S) return grant.accessToken

        try {
            val refreshed = auth.refresh(grant.refreshToken)
            store.grant = refreshed
            refreshed.accessToken
        } catch (e: StravaAuthException) {
            if (e.revoked) store.clearGrant()
            throw e
        }
    }

    companion object {
        /** Refreshes with ten minutes of headroom, so an upload never races the access token's
         *  own expiry mid-request. */
        private const val REFRESH_WINDOW_S = 600L
        private val LOCK = Any()
    }
}
