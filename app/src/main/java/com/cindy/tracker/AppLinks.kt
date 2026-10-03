package com.cindy.tracker

/** Web addresses the app sends the athlete to, kept in one place so each is changed once. */
object AppLinks {

    /**
     * The privacy policy Google Play requires to be reachable from inside the app as well as from
     * the store listing. It is published from its own public repository, because this one is
     * private and GitHub Pages is not available to a private repository on a free plan. Its
     * source is `play/privacy-policy.html` in this repository once the store listing is written,
     * and it says the same things as the PRIVACY section of Help.
     */
    const val PRIVACY_POLICY = "https://alexxgalea.github.io/cindy-privacy/"
}
