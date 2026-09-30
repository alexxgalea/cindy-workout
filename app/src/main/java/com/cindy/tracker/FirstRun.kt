package com.cindy.tracker

import android.content.Context

/**
 * The first-launch flags, kept with every other preference.
 *
 * Apart from [Profile] on purpose, because they are not settings. Nobody edits them from a screen:
 * they record what has already happened to this install, so that the pages and the tour of the
 * camera screen each happen once. When they happen at all is decided by [Onboarding].
 */
class FirstRun(context: Context) {

    private val prefs = context.getSharedPreferences("cindy", Context.MODE_PRIVATE)

    /**
     * Whether the pages are dealt with: shown and finished or skipped, or never needed because the
     * athlete had already used the app. Set either way, so that clearing the records later does
     * not make an existing athlete look new.
     */
    var tutorialSeen: Boolean
        get() = prefs.getBoolean(Onboarding.KEY_TUTORIAL_SEEN, false)
        set(value) {
            prefs.edit().putBoolean(Onboarding.KEY_TUTORIAL_SEEN, value).apply()
        }

    /** Whether the tour of the camera screen is still to come. */
    var hudTourPending: Boolean
        get() = prefs.getBoolean(Onboarding.KEY_HUD_TOUR_PENDING, false)
        set(value) {
            prefs.edit().putBoolean(Onboarding.KEY_HUD_TOUR_PENDING, value).apply()
        }

    /**
     * Whether the athlete has asked never to see the placement guide again. Nobody does that
     * without having met the app before, which is why it counts as history.
     */
    val placementDismissed: Boolean
        get() = prefs.getBoolean(Onboarding.KEY_PLACEMENT_SEEN, false)

    /** Whether to show the pages now. [hasHistory] is whether any session is on record. */
    fun shouldShowTutorial(hasHistory: Boolean): Boolean =
        Onboarding.shouldShowTutorial(tutorialSeen, hasHistory, placementDismissed)

    /** The end of the pages, however they ended: they will not come back, and the tour is next. */
    fun finishPages() {
        tutorialSeen = true
        hudTourPending = true
    }
}
