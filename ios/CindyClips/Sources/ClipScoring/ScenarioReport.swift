import Foundation

/// What became of a scenario. A scenario that could not be run is `skipped`, with its reason,
/// and is never counted as a pass.
public enum ScenarioStatus: String, Sendable {
    case passed, failed, skipped
}

/// One scenario's result, in the shape `run_batch.py` writes (plus `status`, `skipReason`, and
/// `perMovement`, which the Python report has no use for until it is compared).
public struct ScenarioReport: Sendable {
    public var id: String
    public var exercise: String
    public var expectedReps: Int
    public var observedReps: Int
    public var setup: String?
    public var countTimes: [Int64]
    public var frames: [[String: JSONValue]]
    public var failures: [String]
    public var tags: [String]
    public var tolerance: Int
    public var worstHealth: String
    public var lostMs: Int64
    public var perMovement: [String: PerMovement]
    public var skipReason: String?

    public struct PerMovement: Equatable, Sendable {
        public var expected: Int
        public var observed: Int
        public var eventsMs: [Int64]

        public init(expected: Int, observed: Int, eventsMs: [Int64]) {
            self.expected = expected
            self.observed = observed
            self.eventsMs = eventsMs
        }
    }

    public init(id: String, exercise: String, expectedReps: Int = 0, observedReps: Int = 0,
                setup: String? = nil, countTimes: [Int64] = [], frames: [[String: JSONValue]] = [],
                failures: [String] = [], tags: [String] = [], tolerance: Int = 0,
                worstHealth: String = "GOOD", lostMs: Int64 = 0,
                perMovement: [String: PerMovement] = [:], skipReason: String? = nil) {
        self.id = id
        self.exercise = exercise
        self.expectedReps = expectedReps
        self.observedReps = observedReps
        self.setup = setup
        self.countTimes = countTimes
        self.frames = frames
        self.failures = failures
        self.tags = tags
        self.tolerance = tolerance
        self.worstHealth = worstHealth
        self.lostMs = lostMs
        self.perMovement = perMovement
        self.skipReason = skipReason
    }

    public static func skipped(_ scenario: Scenario, because reason: String) -> ScenarioReport {
        ScenarioReport(id: scenario.id, exercise: scenario.exercise.lowercased(),
                       expectedReps: scenario.expectedReps ?? 0,
                       tags: scenario.tags ?? [], skipReason: reason)
    }

    public var status: ScenarioStatus {
        if skipReason != nil { return .skipped }
        return failures.isEmpty ? .passed : .failed
    }

    public var signedError: Int { observedReps - expectedReps }
    public var withinTolerance: Bool { abs(signedError) <= tolerance }
    public var firstCountMs: Int64? { countTimes.first }

    /// Valid and deliberately-invalid clips must never be averaged into one number.
    public var category: String {
        if expectedReps == 0 { return "must-not-count" }
        for tag in ["occlusion", "camera-cut", "known-gap"] where tags.contains(tag) {
            return "difficult-but-valid"
        }
        return "clean-valid"
    }

    /// How many frames each gate refused, most first, ties in the order they first appeared.
    public var rejectionsByGate: [(gate: String, frames: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for frame in frames {
            let key: String
            if case .string(let reason)? = frame["rejection"] { key = reason } else { key = "(scored/none)" }
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        // Stable: Python's sort is, and so is a tie broken by first appearance.
        return order.enumerated()
            .sorted { counts[$0.element]! != counts[$1.element]! ? counts[$0.element]! > counts[$1.element]! : $0.offset < $1.offset }
            .map { ($0.element, counts[$0.element]!) }
    }
}

/// A JSON value, so a report is built without `Any` and written with its nulls.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// NaN and infinity are not JSON; Python's reports hold `null` for the first.
    public static func number(_ value: Double) -> JSONValue {
        value.isFinite ? .double(value) : .null
    }

    /// `round(x, places)` as Python's `round` does it: to the nearest, halves to even.
    public static func rounded(_ value: Float, places: Int) -> JSONValue {
        let scale = pow(10.0, Double(places))
        guard value.isFinite else { return .null }
        return .double((Double(value) * scale).rounded(.toNearestOrEven) / scale)
    }

    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return NSNumber(value: i)
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return s
        case .array(let a): return a.map { $0.foundation }
        case .object(let o): return o.mapValues { $0.foundation }
        }
    }
}

public enum ReportWriter {

    /// The report file, with the keys `run_batch.py` writes for each scenario.
    public static func data(_ reports: [ScenarioReport]) throws -> Data {
        let scenarios: [JSONValue] = reports.map { r in
            var o: [String: JSONValue] = [
                "id": .string(r.id), "exercise": .string(r.exercise), "category": .string(r.category),
                "expectedReps": .int(Int64(r.expectedReps)), "observedReps": .int(Int64(r.observedReps)),
                "signedError": .int(Int64(r.signedError)), "countTolerance": .int(Int64(r.tolerance)),
                "withinTolerance": .bool(r.withinTolerance),
                "setup": r.setup.map(JSONValue.string) ?? .null,
                "countTimestampsMs": .array(r.countTimes.map { .int($0) }),
                "firstCountMs": r.firstCountMs.map(JSONValue.int) ?? .null,
                "rejectionsByGate": .object(Dictionary(uniqueKeysWithValues: r.rejectionsByGate.map { ($0.gate, JSONValue.int(Int64($0.frames))) })),
                "tags": .array(r.tags.map { .string($0) }),
                "failures": .array(r.failures.map { .string($0) }),
                "frames": .array(r.frames.map { .object($0) }),
                "status": .string(r.status.rawValue),
                "skipReason": r.skipReason.map(JSONValue.string) ?? .null,
                "worstHealth": .string(r.worstHealth), "lostMs": .int(r.lostMs)
            ]
            o["perMovement"] = .object(r.perMovement.mapValues {
                .object(["expected": .int(Int64($0.expected)), "observed": .int(Int64($0.observed)),
                         "eventsMs": .array($0.eventsMs.map { .int($0) })])
            })
            return .object(o)
        }
        let root = JSONValue.object(["pose": .string("vision"), "scenarios": .array(scenarios)])
        return try JSONSerialization.data(withJSONObject: root.foundation,
                                          options: [.prettyPrinted, .sortedKeys])
    }
}
