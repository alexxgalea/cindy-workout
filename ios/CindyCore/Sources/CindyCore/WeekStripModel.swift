import Foundation

/// One week as seven circles, so the athlete sees at a glance which days they trained. Port of the
/// behaviour of `WeekStripView`; the drawing is `WeekStripView` in the app.
///
/// Trained days are filled in the earned colour; a day still to come is a small dot, so a week in
/// progress never reads as a week of failures.
public enum WeekStrip {

    public enum DayState: Equatable, Sendable {
        /// Trained: the earned colour, and ringed when it is today.
        case trained(today: Bool)
        /// Today, not trained yet.
        case today
        case missed
        /// Still to come: a small dot.
        case coming
    }

    public struct Day: Equatable, Sendable {
        public let date: LocalDate
        public let state: DayState
    }

    /// The seven days from `weekStart`.
    public static func days(weekStart: LocalDate, trained: Set<LocalDate>, today: LocalDate) -> [Day] {
        (0..<7).map { i in
            let date = weekStart.plusDays(i)
            let state: DayState
            if trained.contains(date) { state = .trained(today: date == today) }
            else if date == today { state = .today }
            else if date.isBefore(today) { state = .missed }
            else { state = .coming }
            return Day(date: date, state: state)
        }
    }

    /// "This week, trained on Monday and Wednesday".
    public static func describe(weekStart: LocalDate, trained: Set<LocalDate>) -> String {
        let days = (0..<7).map { weekStart.plusDays($0) }.filter { trained.contains($0) }
            .map { CalendarModel.fullDays[$0.dayOfWeek.rawValue - 1] }
        switch days.count {
        case 0: return "This week, no sessions yet"
        case 1: return "This week, trained on \(days[0])"
        default: return "This week, trained on \(days.dropLast().joined(separator: ", ")) and \(days.last!)"
        }
    }
}
