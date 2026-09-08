import Foundation

/// A test harness in thirty lines, so the core can be verified without Xcode.
enum Check {
    nonisolated(unsafe) static var run = 0
    nonisolated(unsafe) static var failed = 0
    nonisolated(unsafe) static var suite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        suite = name
        print("\n\(name)")
        body()
    }

    static func expect(_ condition: Bool, _ what: String, line: UInt = #line) {
        run += 1
        if condition {
            print("  ok   \(what)")
        } else {
            failed += 1
            print("  FAIL \(what)   (\(suite):\(line))")
        }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: UInt = #line) {
        run += 1
        if actual == expected {
            print("  ok   \(what)")
        } else {
            failed += 1
            print("  FAIL \(what) — expected \(expected), got \(actual)   (\(suite):\(line))")
        }
    }

    static func close(_ actual: Float, _ expected: Float, _ tolerance: Float,
                      _ what: String, line: UInt = #line) {
        equal(abs(actual - expected) <= tolerance, true, what, line: line)
    }

    static func finish() -> Never {
        print("\n\(run) checks, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
