import XCTest

extension XCUIApplication {
    /// Taps the centres of a `columns` by `rows` grid laid over `frame`, row by row, until `done()`
    /// holds. For a drawn view whose touch is a point on its canvas: the accessibility buttons of its
    /// stops are tapped at the middle of the whole view, which is not where any one day or point is.
    /// A tap on an empty place changes nothing, so scanning is safe.
    ///
    /// `first` are the cells to try before the rest, as (column, row): where the place is expected to be.
    func tapAcross(_ frame: CGRect, columns: Int, rows: Int, first: [(Int, Int)] = [],
                   until done: () -> Bool) -> Bool {
        let origin = coordinate(withNormalizedOffset: .zero)
        var order = first
        for row in 0..<rows {
            for column in 0..<columns where !first.contains(where: { $0 == (column, row) }) {
                order.append((column, row))
            }
        }
        for (column, row) in order {
            let x = frame.minX + frame.width * (CGFloat(column) + 0.5) / CGFloat(columns)
            let y = frame.minY + frame.height * (CGFloat(row) + 0.5) / CGFloat(rows)
            origin.withOffset(CGVector(dx: x, dy: y)).tap()
            if done() { return true }
        }
        return false
    }

    /// Where today falls in the month grid the Progress screen draws: its column and its row among
    /// the week rows, from the phone's own calendar, which is what the app lays the month out by.
    static func todaysCell() -> (column: Int, row: Int) {
        let calendar = Calendar.current
        let now = Date()
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let index = lead + calendar.component(.day, from: now) - 1
        return (index % 7, index / 7)
    }
}
