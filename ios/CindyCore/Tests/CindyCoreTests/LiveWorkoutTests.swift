import XCTest
import CindyCore

/// `LiveWorkout` has no Kotlin test; a flag is not worth one there. Here it is a lock-guarded
/// static, which is worth showing that it reads back what was written.
final class LiveWorkoutTests: XCTestCase {

    /// it starts off, and reads back what was set
    func testItStartsOffAndReadsBackWhatWasSet() {
        XCTAssertFalse(LiveWorkout.active)
        LiveWorkout.active = true
        XCTAssertTrue(LiveWorkout.active)
        LiveWorkout.active = false
        XCTAssertFalse(LiveWorkout.active)
    }
}
