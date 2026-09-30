package com.cindy.tracker

/**
 * When a new athlete is shown around, and where that is remembered.
 *
 * The pages and the tour of the camera screen are for someone who has never used the app. Someone
 * who has, who has finished a session or who has read the placement guide and asked never to see
 * it again, has nothing to learn from a welcome and would only be kept from the camera by one. So
 * they are marked as having seen it without being shown it. A tour that greeted every returning
 * athlete after an update would be the first thing this app ever did to them that was not about
 * their workout.
 *
 * Free of Android types so that the rule can be tested. [FirstRun] holds the flags, in the same
 * preferences as every other setting.
 */
object Onboarding {

    /** Set once the pages have been shown, finished or skipped. They do not come back by themselves. */
    const val KEY_TUTORIAL_SEEN = "tutorial_seen"

    /** Set when the pages are done and the tour of the camera screen has not yet been taken. */
    const val KEY_HUD_TOUR_PENDING = "hud_tour_pending"

    /**
     * Where "Don't show this again" on the placement guide is kept.
     *
     * It lived with the camera screen until it became evidence of something else too: an athlete
     * who has dismissed the guide has used the app before, whatever the records say. One owner for
     * the key means the two readers cannot disagree about what it is called.
     */
    const val KEY_PLACEMENT_SEEN = "placement_guide_dismissed"

    /**
     * Whether to show the pages before the camera opens.
     *
     * Only to a new install: nothing seen, no session on record, the placement guide never
     * dismissed, and the camera's permission not already held. Each of the last three is proof
     * enough that the app is not new to them, and the records alone are not: a person can dismiss
     * the guide, or only ever run the setup check, and close the app before finishing anything.
     *
     * The permission is the evidence that reaches furthest back. Android starts every install
     * without it, so a fresh one cannot have it, while an athlete who updated from a version that
     * predates these pages has held it since the first time they opened the camera.
     */
    fun shouldShowTutorial(
        seen: Boolean,
        hasHistory: Boolean,
        placementDismissed: Boolean,
        cameraGranted: Boolean
    ): Boolean = !seen && !hasHistory && !placementDismissed && !cameraGranted
}
