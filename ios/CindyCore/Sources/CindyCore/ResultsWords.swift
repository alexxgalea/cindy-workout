import Foundation

/// The words the session page's view drew itself, with nothing to pin them to the Android page's.
/// The page models hold the sentences they build; these are the titles, eyebrows and invitations
/// that sat in the view, and each is the literal in `activity_results.xml` or `ResultsActivity.kt`.
/// `ResultsWordsTests` reads them off the Kotlin.
public enum ResultsWords {
    public static let trackTitle = "ROUND BY ROUND"
    public static let movementsTitle = "MOVEMENTS"
    public static let compareTitle = "COMPARED WITH"
    public static let timelineTitle = "TIMELINE"
    public static let splitsTitle = "ROUND SPLITS"
    public static let heartTitle = "HEART RATE"
    public static let detailsTitle = "DETAILS"
    public static let liftedEyebrow = "YOU LIFTED"
    public static let burnedEyebrow = "YOU BURNED"
    public static let weightInviteTitle = "Your weight"
    public static let weightInviteValue = "Add it to see what you lifted and burned"
    public static let zonesInviteTitle = "Heart-rate zones"
    public static let zonesInviteValue = "Add your birth year to see them"
    public static let timeInZone = "TIME IN ZONE"
    public static let hardestRound = "Hardest round"
    public static let scrubHint = "Drag across the chart to scrub through the session."
}
