import Foundation

/// A month, with the days that were trained filled in. Port of the behaviour of `CalendarView`;
/// the drawing is `CalendarView` in the app.
///
/// The point is the shape of the thing: a streak reads as a run of filled cells and a week off as
/// a hole. A tap on a trained day reports it, and only a tap: a finger that travelled further than
/// the slop was a drag. Each trained day is its own screen reader stop.
public final class CalendarModel {

    /// How a day's cell is drawn.
    public enum CellState: Sendable {
        /// Trained, and in the current streak: the earned colour.
        case streak
        /// Trained, outside the current streak: white.
        case trained
        /// Today, not trained yet: a ring.
        case today
        /// Still to come: faint.
        case future
        case past
    }

    public struct Cell: Equatable, Sendable {
        public let day: Int
        public let column: Int
        public let row: Int
        public let state: CellState
        /// Today, whether or not it was trained: the digits are bold.
        public let isToday: Bool
        public let trained: Bool
    }

    /// One trained day as a screen reader sees it.
    public struct Stop: Equatable, Sendable {
        public let date: LocalDate
        public let spoken: String
    }

    /// A header row plus six week rows covers every month layout without reflowing.
    public static let weeksShown = 6
    public static let columns = 7

    /// Called with the date of a trained day the athlete taps; other cells do nothing.
    public var onDayTap: ((LocalDate) -> Void)?

    public let firstDayOfWeek: DayOfWeek
    private let monthName: (YearMonth) -> String

    public private(set) var month = YearMonth(2000, 1)
    public private(set) var trained: Set<LocalDate> = []
    public private(set) var today = LocalDate(2000, 1, 1)
    public private(set) var streak: Set<LocalDate> = []
    private var downX = 0.0
    private var downY = 0.0

    /// `monthName` is how the phone says a month, in full; English by default.
    public init(firstDayOfWeek: DayOfWeek, monthName: @escaping (YearMonth) -> String = CalendarModel.englishMonth) {
        self.firstDayOfWeek = firstDayOfWeek
        self.monthName = monthName
    }

    public static let fullMonths = ["January", "February", "March", "April", "May", "June", "July", "August",
                                    "September", "October", "November", "December"]
    public static let fullDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public static func englishMonth(_ m: YearMonth) -> String { fullMonths[m.month - 1] }

    /// `streak` is the run of days to paint in the achievement colour; a trained day outside it
    /// stays white, so the current run reads apart from the history behind it.
    public func show(_ month: YearMonth, trained: Set<LocalDate>, today: LocalDate, streak: Set<LocalDate> = []) {
        self.month = month
        self.trained = trained
        self.today = today
        self.streak = streak
    }

    /// "September 2026, trained on 1 day".
    public var summary: String {
        let inMonth = trained.filter { $0.yearMonth == month }.count
        return "\(monthName(month)) \(month.year), trained on \(inMonth) day\(inMonth == 1 ? "" : "s")"
    }

    // MARK: geometry

    public func cellSize(width: Double) -> Double { width / Double(Self.columns) }

    /// A header row plus six weeks.
    public func height(width: Double) -> Double { cellSize(width: width) * Double(Self.weeksShown + 1) }

    /// How far into the week the 1st falls, given where this locale starts its weeks.
    public var lead: Int { CalendarGrid.lead(month, firstDayOfWeek: firstDayOfWeek) }

    /// The centre of the cell holding `day`.
    public func centre(ofDay day: Int, width: Double) -> (x: Double, y: Double) {
        let cell = cellSize(width: width)
        let index = lead + day - 1
        return (cell * (Double(index % 7) + 0.5), cell * (Double(index / 7 + 1) + 0.5))
    }

    /// The weekday initials' x, left to right, in the locale's own week order.
    public func headerDays() -> [DayOfWeek] {
        (0..<7).map { DayOfWeek(rawValue: (firstDayOfWeek.rawValue - 1 + $0) % 7 + 1)! }
    }

    public func cells() -> [Cell] {
        (1...month.lengthOfMonth).map { day in
            let date = month.atDay(day)
            let index = lead + day - 1
            let didTrain = trained.contains(date)
            let isToday = date == today
            let state: CellState
            if didTrain { state = streak.contains(date) ? .streak : .trained }
            else if isToday { state = .today }
            else if date.isAfter(today) { state = .future }
            else { state = .past }
            return Cell(day: day, column: index % 7, row: index / 7 + 1, state: state, isToday: isToday, trained: didTrain)
        }
    }

    // MARK: touch

    private func date(x: Double, y: Double, width: Double) -> LocalDate? {
        let cell = cellSize(width: width)
        return CalendarGrid.dateAt(month, firstDayOfWeek: firstDayOfWeek, col: Int(x / cell), row: Int(y / cell))
    }

    public func touchDown(x: Double, y: Double) {
        downX = x
        downY = y
    }

    /// A tap on a trained day opens it; without a listener the view stays inert. A finger that
    /// travelled further than the touch slop was a drag, not a tap, so it opens nothing.
    public func touchUp(x: Double, y: Double, width: Double) {
        guard let listener = onDayTap else { return }
        if hypot(x - downX, y - downY) >= TouchTracker.defaultSlop { return }
        if let date = date(x: x, y: y, width: width), trained.contains(date) { listener(date) }
    }

    // MARK: screen reader

    /// The trained days of the shown month, in order.
    public var stops: [Stop] {
        trained.filter { $0.yearMonth == month }.sorted().map { date in
            let spoken = Self.spokenDate(date) + ", trained" + (streak.contains(date) ? ", in your current streak" : "")
            return Stop(date: date, spoken: spoken)
        }
    }

    /// "Monday 7 September".
    public static func spokenDate(_ date: LocalDate) -> String {
        "\(fullDays[date.dayOfWeek.rawValue - 1]) \(date.day) \(fullMonths[date.month - 1])"
    }

    public func activate(stop i: Int) {
        guard let listener = onDayTap, stops.indices.contains(i) else { return }
        listener(stops[i].date)
    }
}
