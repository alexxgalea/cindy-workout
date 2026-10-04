import XCTest
import CindyCore

/// The words and the order of the camera-screen tour. `HudTourTest.kt` lays the list against the
/// inflated Android layout (Robolectric), which has no counterpart here until the spotlight is
/// drawn (P14); what can be held to the Kotlin now is the list itself, so this reads it from
/// `HudTour.kt` and compares every control, title and caption.
final class HudTourTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    private struct KotlinStep: Equatable { let control: String; let title: String; let body: String }

    private func kotlinSteps() throws -> [KotlinStep] {
        let url = Self.root.appendingPathComponent("app/src/main/java/com/cindy/tracker/HudTour.kt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(
            pattern: "SpotlightView\\.Step\\(\\s*hud\\.(\\w+),\\s*\"((?:[^\"\\\\]|\\\\.)*)\",\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*\\)",
            options: [.dotMatchesLineSeparators])
        let all = NSRange(source.startIndex..., in: source)
        return pattern.matches(in: source, range: all).map { m in
            func group(_ i: Int) -> String { String(source[Range(m.range(at: i), in: source)!]) }
            return KotlinStep(control: group(1), title: group(2), body: group(3))
        }
    }

    /// the tour has a step for each of the seven controls it names
    func testTheTourHasAStepForEachOfTheSevenControlsItNames() {
        XCTAssertEqual(HudTour.steps.count, 7)
        XCTAssertEqual(HudTour.steps.map { $0.target }, HudTour.Target.allCases)
        XCTAssertEqual(Set(HudTour.steps.map { $0.target }).count, 7)
    }

    /// each step says its title and what it is for
    func testEachStepSaysItsTitleAndWhatItIsFor() {
        for step in HudTour.steps {
            XCTAssertFalse(step.title.isEmpty, "\(step.target)")
            XCTAssertTrue(step.body.hasSuffix("."), "\(step.target): \(step.body)")
        }
        XCTAssertEqual(Set(HudTour.steps.map { $0.title }).count, 7, "titles are unique")
    }

    /// the list is the Kotlin's, control by control, in the same order and the same words
    func testTheListIsTheKotlinsControlByControlInTheSameOrderAndTheSameWords() throws {
        let kotlin = try kotlinSteps()
        XCTAssertEqual(kotlin.count, 7, "the reader found \(kotlin.count) steps in HudTour.kt")
        XCTAssertEqual(HudTour.steps.map { $0.target.rawValue }, kotlin.map { $0.control })
        XCTAssertEqual(HudTour.steps.map { $0.title }, kotlin.map { $0.title })
        XCTAssertEqual(HudTour.steps.map { $0.body }, kotlin.map { $0.body })
    }
}
