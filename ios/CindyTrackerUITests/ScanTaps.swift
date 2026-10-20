import XCTest

extension XCUIApplication {
    /// Taps the centres of a `columns` by `rows` grid laid over `frame`, row by row, until `done()`
    /// holds. For a drawn view whose touch is a point on its canvas: the accessibility buttons of its
    /// stops are tapped at the middle of the whole view, which is not where any one day or point is.
    /// A tap on an empty place changes nothing, so scanning is safe.
    func tapAcross(_ frame: CGRect, columns: Int, rows: Int, until done: () -> Bool) -> Bool {
        let origin = coordinate(withNormalizedOffset: .zero)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = frame.minX + frame.width * (CGFloat(column) + 0.5) / CGFloat(columns)
                let y = frame.minY + frame.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                origin.withOffset(CGVector(dx: x, dy: y)).tap()
                if done() { return true }
            }
        }
        return false
    }
}
