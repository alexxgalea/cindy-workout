import XCTest
import CindyFixtures

/// `JavaRandom` has to be `java.util.Random`, or a test ported with its seed is not the same test.
/// The expected numbers are what the JVM gives.
final class JavaRandomTests: XCTestCase {

    func testTheStreamIsTheJVMs() {
        var zero = JavaRandom(seed: 0)
        XCTAssertEqual(zero.nextInt(), -1155484576, "Random(0).nextInt(), the first value")
        XCTAssertEqual(zero.nextInt(), -723955400, "and the second")

        var answer = JavaRandom(seed: 42)
        XCTAssertEqual(answer.nextInt(), -1170105035, "Random(42).nextInt(), the first value")

        var tens = JavaRandom(seed: 42)
        XCTAssertEqual((0..<5).map { _ in tens.nextInt(10) }, [0, 3, 8, 4, 0],
                       "Random(42).nextInt(10), five times: the well-known sequence")
        var hundreds = JavaRandom(seed: 42)
        XCTAssertEqual((0..<5).map { _ in hundreds.nextInt(100) }, [30, 63, 48, 84, 70],
                       "and nextInt(100), which is the same draws taken mod 100")
    }

    func testABoundIsRespected() {
        var random = JavaRandom(seed: 7)
        let draws = (0..<1000).map { _ in random.nextInt(60) }
        XCTAssertTrue(draws.allSatisfy { $0 >= 0 && $0 < 60 }, "every draw is inside the bound")
        XCTAssertGreaterThan(Set(draws).count, 50, "and they cover it")
        var powers = JavaRandom(seed: 7)
        XCTAssertTrue((0..<200).allSatisfy { _ in (0..<64).contains(powers.nextInt(64)) },
                      "a power of two takes the other branch, and stays inside too")
    }

    func testFloatsAreInTheUnitInterval() {
        var random = JavaRandom(seed: 7)
        let draws = (0..<1000).map { _ in random.nextFloat() }
        XCTAssertTrue(draws.allSatisfy { $0 >= 0 && $0 < 1 }, "0 up to but not including 1")
    }
}
