import Foundation

/// The Progress screen with its state: what the chart plots and over how long, which kind of Cindy
/// it is about, and the month the calendar shows. The page is built again, whole, whenever a choice
/// changes or the board does. Port of `RecordsActivity`'s state.
public final class ProgressModel {

    public private(set) var input: ProgressInput
    public private(set) var metric = ProgressMetric.score
    public private(set) var range = ProgressRange.all
    /// The kind of Cindy the chart and the peaks are about; follows the latest until chosen.
    public private(set) var category: CindyProfile?
    private var categoryChosen = false
    /// The month the calendar is showing; the athlete can page back through it.
    public private(set) var shownMonth: YearMonth
    public private(set) var page: ProgressPage

    /// Called after the page has been built again.
    public var onChange: (() -> Void)?

    public init(_ input: ProgressInput) {
        self.input = input
        shownMonth = input.today.yearMonth
        category = Progress.defaultCategory(input.attempts)
        page = ProgressPageBuilder.build(input, metric: .score, range: .all, category: category, month: shownMonth)
        rebuild(notify: false)
    }

    private func rebuild(notify: Bool = true) {
        if !categoryChosen || !Progress.categories(input.attempts).contains(where: { $0 == category }) {
            category = Progress.defaultCategory(input.attempts)
        }
        shownMonth = ProgressPageBuilder.clamped(shownMonth, input)
        page = ProgressPageBuilder.build(input, metric: metric, range: range, category: category, month: shownMonth)
        if notify { onChange?() }
    }

    // MARK: the chips

    /// A tap on the metric chip at `index`; only a change rebuilds.
    public func chooseMetric(_ index: Int) {
        guard ProgressMetric.allCases.indices.contains(index), ProgressMetric.allCases[index] != metric else { return }
        metric = ProgressMetric.allCases[index]
        rebuild()
    }

    public func chooseRange(_ index: Int) {
        guard ProgressRange.allCases.indices.contains(index), ProgressRange.allCases[index] != range else { return }
        range = ProgressRange.allCases[index]
        rebuild()
    }

    /// The peaks follow the category, so choosing one rebuilds the whole page.
    public func chooseCategory(_ index: Int) {
        let categories = Progress.categories(input.attempts)
        guard categories.indices.contains(index), page.progress?.category != index else { return }
        category = categories[index]
        categoryChosen = true
        rebuild()
    }

    // MARK: the calendar

    public func showPreviousMonth() {
        guard page.calendar?.canGoBack == true else { return }
        shownMonth = ProgressPageBuilder.shifted(shownMonth, by: -1)
        rebuild()
    }

    public func showNextMonth() {
        guard page.calendar?.canGoForward == true else { return }
        shownMonth = ProgressPageBuilder.shifted(shownMonth, by: 1)
        rebuild()
    }

    /// The sessions of one trained day, or nil when there are none.
    public func daySheet(_ date: LocalDate) -> DaySheet? { ProgressPageBuilder.daySheet(input, date) }

    // MARK: the board

    public var clearQuestion: ClearQuestion? { ProgressPageBuilder.clearQuestion(input) }

    /// The board changed (CLEAR, or a session was saved): build the page again from `attempts`.
    public func reload(_ attempts: [Attempt]) {
        input.attempts = attempts
        rebuild()
    }

    // MARK: words that follow the finger

    /// What the card says under the metric chips: the whole range with nothing selected, else the
    /// point `selected`.
    public func readout(selected: Int?) -> Readout {
        guard let card = page.progress else { return Readout("", "") }
        guard let i = selected, let points = Self.points(card.chart), points.indices.contains(i) else {
            return card.overview
        }
        return Progress.describe(metric, points, i, zone: input.zone)
    }

    /// What a screen reader says for point `i`.
    public func spoken(point i: Int) -> String {
        let r = readout(selected: i)
        return "\(r.headline). \(r.detail)"
    }

    /// The session OPEN reopens for the selected point: only a line point is one session, and a bar
    /// is a week of them.
    public func openTarget(selected: Int?) -> Int64? {
        guard page.progress?.opensSessions == true, let i = selected,
              let points = Self.points(page.progress?.chart), points.indices.contains(i) else { return nil }
        return points[i].attempt?.atMillis
    }

    private static func points(_ chart: ChartData?) -> [ProgressPoint]? {
        switch chart {
        case .bars(let points, _)?: return points
        case .line(let points, _, _, _, _, _)?: return points
        case nil: return nil
        }
    }
}
