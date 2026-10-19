import Foundation

/// Web addresses the app sends the athlete to, kept in one place so each is changed once.
/// Port of `AppLinks.kt`.
public enum AppLinks {

    /// The privacy policy the stores require to be reachable from inside the app as well as from the
    /// listing. It is published from its own public repository, because this one is private and
    /// GitHub Pages is not available to a private repository on a free plan, and it says the same
    /// things as the PRIVACY section of Help.
    public static let privacyPolicy = "https://alexxgalea.github.io/cindy-privacy/"

    /// CrossFit's own page for Cindy, where the workout, the scaled version, the score tiers and the
    /// pacing quotes on the Help screen come from. (`HelpActivity.SOURCE`.)
    public static let crossfitCindy = "https://www.crossfit.com/cindy"
}
