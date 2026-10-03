import XCTest
import CindyCore

/// Found by breaking `RepLog` on purpose: removing one mark however far the total fell passed
/// every ported test, because none of them undoes more than one rep at a time. Not in the Kotlin
/// suite, which has the same gap.
final class RepLogFallTests: XCTestCase {

    /// a fall of three removes the last three marks, not one
    func testAFallOfThreeRemovesTheLastThreeMarks() {
        let log = RepLog()
        log.start()
        for i in 0..<5 { log.follow(totalReps: i + 1, manualReps: 0, movement: .pullup, clockMs: Int64(i)) }
        log.follow(totalReps: 2, manualReps: 0, movement: .pullup, clockMs: 9)
        XCTAssertEqual(log.marks.map { $0.clockMs }, [0, 1])
    }
}
