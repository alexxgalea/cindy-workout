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

    /**
     * Lets a test build a screen as if this were a build with Strava credentials, or force one
     * back to a build with none.
     *
     * [available] is otherwise derived once from [BuildConfig] at class-init and is always false
     * under a unit test — there is no `strava.properties` in CI, and nothing shadows
     * `BuildConfig` the way Robolectric shadows the platform. Production code never touches
     * this; it stays null and [available] reads the real credentials as normal. [MenuActivity]
     * and [ResultsActivity] share this one seam rather than each keeping a static of their own
     * to reset, so a test cannot fix one screen's answer while leaving the other's stale. Tests
     * must reset it in a `finally` or `@After`, since it is a static and outlives the activity
     * under test.
     */
    internal var availableForTest: Boolean? = null

    /** False for CI and a fresh clone with no `strava.properties`. The whole feature hides. */
    val available: Boolean
        get() = availableForTest ?: (clientId.isNotBlank() && clientSecret.isNotBlank())

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
     * `StravaAuthActivity`.
     */
    const val REDIRECT_URI = "com.cindy.tracker://localhost/strava"

    /** `activity:write` is what the upload needs; `read` is what shows the athlete's name back. */
    const val SCOPE = "read,activity:write"
}
