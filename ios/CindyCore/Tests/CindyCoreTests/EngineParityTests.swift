import XCTest
import CindyCore
import CindyFixtures

/// Replays `tests/parity/plan.csv` through the Swift engine and compares every frame's decision
/// with `tests/parity/trace_jvm.csv`, which `EngineParityTraceTest` writes from the production
/// Kotlin engine. Two implementations of the same rules drift, and this is what says they have not:
/// a divergence is reported as the first frame of a trace that differs and the columns that do,
/// not as "the counts disagree".
///
/// Mirrors `EngineParityTraceTest.kt` and `tools/video_regression/parity_check.py`. It writes
/// nothing: the Swift trace is built in memory.
///
/// Any change to the Kotlin engine changes `trace_jvm.csv`, and this fails until the Swift side
/// follows. That is the point.
final class EngineParityTests: XCTestCase {

    private static let columns = [
        "traceId", "step", "tMs", "angle", "kpSum", "event", "count", "state", "signal",
        "learnedRange", "calibrated", "hint", "minConfidence", "confidenceAdequate", "poseLegible",
        "barGateOpen", "headAboveBar", "resetSeen", "rejection"
    ]

    func testEveryFrameMatchesTheKotlinEngine() throws {
        let root = try repositoryRoot()
        let plan = try String(contentsOf: root.appendingPathComponent("tests/parity/plan.csv"),
                              encoding: .utf8)
        let reference = try String(contentsOf: root.appendingPathComponent("tests/parity/trace_jvm.csv"),
                                   encoding: .utf8)

        let expected = Self.records(reference).dropFirst().map { Self.fields($0) }
        var expectedByTrace: [String: [[String]]] = [:]
        for row in expected { expectedByTrace[row[0], default: []].append(row) }

        var steps: [String: [[String]]] = [:]
        var order: [String] = []
        for record in Self.records(plan).dropFirst() {
            let cells = record.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if steps[cells[0]] == nil { order.append(cells[0]) }
            steps[cells[0], default: []].append(cells)
        }

        var compared = 0
        var failures: [String] = []
        for id in order {
            let actual = try trace(id, steps[id]!)
            guard let want = expectedByTrace[id] else {
                failures.append("\(id): no rows in trace_jvm.csv")
                continue
            }
            if actual.count != want.count {
                failures.append("\(id): \(actual.count) frames here, \(want.count) in the Kotlin trace")
                continue
            }
            for (a, w) in zip(actual, want) {
                compared += 1
                let differing = zip(Self.columns, zip(a, w)).filter { $0.1.0 != $0.1.1 }
                if !differing.isEmpty {
                    let columns = differing.map { "\($0.0): kotlin \($0.1.1), swift \($0.1.0)" }
                    failures.append("\(id) step \(a[1]): " + columns.joined(separator: "; "))
                    break  // the first divergent frame localises it; later ones just follow
                }
            }
        }

        XCTAssertEqual(failures, [], "every frame of every runnable trace must match the Kotlin")
        XCTAssertGreaterThan(compared, 0, "something was compared")
        XCTAssertEqual(order.count, 20, "all twenty traces in the plan ran")
        print("Parity: \(compared) frames compared across \(order.count) traces")
    }

    // MARK: - one trace

    private func trace(_ id: String, _ rows: [[String]]) throws -> [[String]] {
        let first = rows[0]
        let exercise: Exercise
        switch first[1] {
        case "pullup": exercise = .pullup
        case "pushup": exercise = .pushup
        case "squat": exercise = .squat
        default: throw ParityError.unknown("exercise \(first[1]) in \(id)")
        }
        guard let pull = PullVariant(rawValue: first[6]),
              let squat = SquatVariant(rawValue: first[7]) else {
            throw ParityError.unknown("movement variant in \(id)")
        }
        // The two columns the plan grew for the heels-flat squat. A plan without them is the
        // standard air squat with smart counting off, which is what every older row means.
        let smart = first.count > 8 && first[8] == "true"
        let engine = WorkoutEngine(fixedExercise: exercise,
                                   profile: CindyProfile(pull: pull, squat: squat),
                                   smartSquats: smart)

        return try rows.map { row in
            let angle = Float(row[5])!
            let now = Int64(row[3])! * Int64(row[4])!
            let keypoints: [Keypoint]
            switch row[2] {
            case "pullup": keypoints = PoseFixtures.pullup(angle)
            case "pushup": keypoints = PoseFixtures.pushup(angle)
            case "squat": keypoints = PoseFixtures.squat(angle)
            case "bandsetup": keypoints = PoseFixtures.bandSetup()
            case "invertedrow": keypoints = PoseFixtures.invertedRow(angle)
            default: throw ParityError.unknown("builder \(row[2]) in \(id)")
            }
            let event = engine.onFrame(keypoints, now: now)
            let d = engine.diagnostics
            let sum = keypoints.reduce(0.0) { $0 + Double($1.x + $1.y) }
            return [
                id, row[4], String(now), row[5], Self.fixed3(sum),
                Self.name(of: event), String(engine.reps), engine.countingState,
                Self.fixed3(Double(engine.signal)), Self.fixed3(Double(engine.learnedRange)),
                String(engine.calibrated), engine.hint, Self.fixed3(Double(d.minimumConfidence)),
                String(d.scoringConfidenceAdequate), String(d.poseLegible), String(d.barGateOpen),
                String(d.headAboveBar), String(d.resetBelowBarSeen), d.rejectionReason ?? ""
            ]
        }
    }

    private enum ParityError: Error { case unknown(String), noRepository }

    // MARK: - formatting, as the Kotlin does it

    /// `EngineParityTraceTest.round`: `String.format(Locale.US, "%.3f", value)`, with NaN spelled
    /// "nan" because it has no stable spelling across languages.
    ///
    /// Java rounds the exact value half up; C's printf rounds an exact tie to even, so
    /// 0.0625 is "0.063" in Java and "0.062" in C. The digits are taken from a long printf and
    /// rounded by hand to match Java.
    static func fixed3(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        let negative = value.sign == .minus
        let long = String(format: "%.40f", abs(value))
        let parts = long.split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(String(parts[0]) + String(parts[1].prefix(3))).map { Int(String($0))! }
        if let next = parts[1].dropFirst(3).first, Int(String(next))! >= 5 {
            var i = digits.count - 1
            while i >= 0 {
                if digits[i] == 9 { digits[i] = 0; i -= 1 } else { digits[i] += 1; break }
            }
            if i < 0 { digits.insert(1, at: 0) }
        }
        let text = digits.map(String.init).joined()
        let whole = text.dropLast(3), fraction = text.suffix(3)
        return (negative ? "-" : "") + whole + "." + fraction
    }

    /// The trace spells `RepEvent` as the Kotlin enum's name.
    static func name(of event: RepEvent) -> String {
        switch event {
        case .none: return "NONE"
        case .rep: return "REP"
        case .undo: return "UNDO"
        case .exerciseDone: return "EXERCISE_DONE"
        case .roundDone: return "ROUND_DONE"
        }
    }

    // MARK: - reading the files

    /// Lines, joined back up when a quoted field spans one (the Kotlin trace never does, but a
    /// hint could).
    static func records(_ text: String) -> [String] {
        var out: [String] = [], current = "", quotes = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            current += (current.isEmpty ? "" : "\n") + line
            quotes += line.filter { $0 == "\"" }.count
            if quotes % 2 == 0 { out.append(current); current = ""; quotes = 0 }
        }
        return out
    }

    /// One CSV record into its fields: quoted, with `""` for a quote inside one.
    static func fields(_ record: String) -> [String] {
        var out: [String] = [], current = "", quoted = false
        let chars = Array(record)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { current.append("\""); i += 1 }
                    else { quoted = false }
                } else { current.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                out.append(current); current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        out.append(current)
        return out
    }

    private func repositoryRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.gradle.kts").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw ParityError.noRepository
    }
}

/// The parity test is only as good as the way it spells numbers, so the spelling is tested.
final class ParityFormattingTests: XCTestCase {

    func testNumbersAreSpelledLikeJavaAtThreeDecimals() {
        XCTAssertEqual(EngineParityTests.fixed3(175), "175.000", "a whole number")
        XCTAssertEqual(EngineParityTests.fixed3(-584.519), "-584.519", "a negative, as in the trace")
        XCTAssertEqual(EngineParityTests.fixed3(0.0625), "0.063", "an exact tie rounds up, where C's printf rounds to even")
        XCTAssertEqual(EngineParityTests.fixed3(0.1875), "0.188", "another exact tie")
        XCTAssertEqual(EngineParityTests.fixed3(9.9996), "10.000", "rounding carries into the whole part")
        XCTAssertEqual(EngineParityTests.fixed3(0.9996), "1.000", "and across a zero")
        XCTAssertEqual(EngineParityTests.fixed3(-0.0004), "-0.000", "a negative that rounds to zero keeps its sign, as Java does")
        XCTAssertEqual(EngineParityTests.fixed3(0), "0.000", "zero")
        XCTAssertEqual(EngineParityTests.fixed3(.nan), "nan", "NaN is spelled nan")
    }

    func testQuotedFieldsAreReadBack() {
        XCTAssertEqual(EngineParityTests.fields("\"a\",\"b,c\",\"\",\"say \"\"hi\"\"\""),
                       ["a", "b,c", "", "say \"hi\""], "commas and doubled quotes inside quotes")
        XCTAssertEqual(EngineParityTests.fields("plain,fields,here"), ["plain", "fields", "here"],
                       "unquoted fields too")
    }
}
