package com.cindy.tracker

import org.junit.rules.ExternalResource

/**
 * Pins [StravaConfig.available] to false for a test class, so its result does not depend on
 * whether the machine running it has a `strava.properties`.
 *
 * With credentials present the results screen shows its Strava row and watches WorkManager for
 * the upload, and Robolectric does not start WorkManager the way the app's manifest does. A test
 * about something else then fails on a developer's machine and passes on CI, which has no
 * credentials. Tests that are about Strava set [StravaConfig.availableForTest] themselves, as
 * [StravaScreenTest] does.
 */
class NoStravaCredentials : ExternalResource() {

    private var before: Boolean? = null

    override fun before() {
        before = StravaConfig.availableForTest
        StravaConfig.availableForTest = false
    }

    override fun after() {
        StravaConfig.availableForTest = before
    }
}
