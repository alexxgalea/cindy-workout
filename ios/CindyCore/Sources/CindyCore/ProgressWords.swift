import Foundation

/// The words the Progress screen's view drew itself, with nothing to pin them to the Android
/// screen's. The page model holds the sentences it builds; these are the title and the line under
/// it, the section titles, the chart's OPEN button and the calendar arrows' names, and each is the
/// literal in `activity_records.xml` or `RecordsActivity.kt`. `ProgressWordsTests` reads them off
/// the Kotlin.
public enum ProgressWords {
    public static let title = "Progress"
    public static let subtitle = "Cindy — AMRAP 20:00"
    public static let thisWeekTitle = "THIS WEEK"
    public static let progressTitle = "PROGRESS"
    public static let peaksTitle = "PEAKS"
    public static let leaderboardTitle = "LEADERBOARD"
    public static let open = "OPEN"
    public static let previousMonth = "Previous month"
    public static let nextMonth = "Next month"
}
