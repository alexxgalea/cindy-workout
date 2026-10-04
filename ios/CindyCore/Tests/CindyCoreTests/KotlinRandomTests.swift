import XCTest
import CindyFixtures

/// `KotlinRandom` has to be `kotlin.random.Random`, or a test ported with its seed is not the same
/// test. The expected numbers are what the JVM gives (Kotlin 2.0, `Random(7)` and `Random(2026)`).
final class KotlinRandomTests: XCTestCase {

    func testTheStreamIsKotlins() {
        var r = KotlinRandom(seed: 7)
        XCTAssertEqual((0..<6).map { _ in r.nextInt() },
                       [-182312124, 11901178, -1941452650, 1600128533, 1560878315, -1270558976])
    }

    func testRangesAreKotlinsRejectionLoops() {
        var a = KotlinRandom(seed: 7)
        XCTAssertEqual((0..<8).map { _ in a.nextInt(0, 400) }, [386, 189, 123, 266, 357, 160, 52, 394])
        XCTAssertEqual((0..<5).map { _ in a.nextLong(30_000, 1_200_000) }, [302747, 616127, 746392, 523122, 1087425])
        XCTAssertEqual((0..<5).map { _ in a.nextInt(10) }, [8, 1, 1, 2, 0])
        XCTAssertEqual((0..<5).map { _ in a.nextLong(5_001, 60_000) }, [33263, 40584, 22642, 39886, 14776])

        var b = KotlinRandom(seed: 2026)
        XCTAssertEqual((0..<8).map { _ in b.nextInt(0, 400) }, [167, 108, 173, 141, 228, 53, 126, 393])
        XCTAssertEqual((0..<4).map { _ in b.nextInt(25, 235) }, [156, 144, 50, 230])
        XCTAssertEqual((0..<4).map { _ in b.nextLong(500, 2_500) }, [993, 1048, 764, 1571])
        XCTAssertEqual((0..<4).map { _ in b.nextLong(0, 4_000) }, [2938, 2607, 3130, 3083])
    }

    func testPowersOfTwoTakeTheHighBits() {
        var c = KotlinRandom(seed: 2026)
        XCTAssertEqual((0..<6).map { _ in c.nextInt(0, 64) }, [54, 32, 14, 61, 34, 52])
        XCTAssertEqual((0..<3).map { _ in c.nextLong(0, 1 << 40) }, [196048160307, 846426695791, 199994828047])
        XCTAssertEqual((0..<3).map { _ in c.nextLong(0, 1024) }, [1, 16, 110])
    }
}
