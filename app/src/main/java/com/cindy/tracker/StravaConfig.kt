package com.cindy.tracker

/**
 * The Strava feature's fixed facts: the API hosts, the OAuth scope, and whether this particular
 * build was given credentials to use any of it.
 *
 * [clientId] and [clientSecret] come from [BuildConfig], which bakes in whatever
 * `strava.properties` held at build time (see `app/build.gradle.kts`) — empty strings when the
 * file was absent, which is true for CI and for a fresh clone. [available] turns that fact into
 * the one the rest of the app should act on: a build with no credentials does not have the
 * feature, so the menu says "Not available in this build" instead of the app reaching for a
 * client secret that was never there.
 */
object StravaConfig {

    val clientId: String = BuildConfig.STRAVA_CLIENT_ID
    val clientSecret: String = BuildConfig.STRAVA_CLIENT_SECRET

    /** False for CI and a fresh clone with no `strava.properties`. The whole feature hides. */
    val available: Boolean = clientId.isNotBlank() && clientSecret.isNotBlank()

    /**
     * The v3 API host. Strava opens `https://api-v3.strava.com` as an alternative on
     * 2027-01-04. Keep the base in this one constant, so that moving to it — if it ever
     * happens — is a one-line change instead of a search-and-replace across the feature.
     */
    const val API_BASE = "https://www.strava.com/api/v3"

    const val OAUTH_BASE = "https://www.strava.com/oauth"

    /**
     * A reverse-DNS scheme (RFC 8252) with host `localhost`, which Strava whitelists as an
     * Authorization Callback Domain without our own web server to receive it. Handled by
     * `StravaAuthActivity` (S2).
     */
    const val REDIRECT_URI = "com.cindy.tracker://localhost/strava"

    /** `activity:write` is what the upload needs; `read` is what shows the athlete's name back. */
    const val SCOPE = "read,activity:write"
}
