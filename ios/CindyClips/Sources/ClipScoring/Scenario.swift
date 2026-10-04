import Foundation
import CindyCore

/// One labelled clip, as `tests/scenarios/*.json` describes it. The same files `run_batch.py` and
/// the Android job read, so a clip is labelled once and scored by all three.
///
/// Keys this tool has no use for (`notes`, `quality`, `labelledBottomsMs`, `model`, …) are
/// ignored. `model` names a MoveNet variant, and Vision has one network and no choice of it.
public struct Scenario: Decodable, Equatable, Sendable {
    public var id: String
    public var video: String
    public var exercise: String
    public var expectedReps: Int?
    public var expectedSetup: String?
    public var expectedCountingState: String?
    public var expectedRepEventsMs: [Int]?
    public var eventToleranceMs: Int?
    public var countTolerance: Int?
    public var expectedTracking: String?
    public var pull: String?
    public var bar: Bar?
    public var light: Light?
    public var tags: [String]?
    /// `"skip"` is the SKIP button, in a `cindy` scenario.
    public var setup: String?
    public var skipTo: [SkipTo]?
    public var expectedRepsByMovement: [String: Int]?

    public struct Bar: Decodable, Equatable, Sendable {
        public var mode: String?
        public var yNormalized: Float?
        public var xMinNormalized: Float?
        public var xMaxNormalized: Float?

        public init(mode: String? = nil, yNormalized: Float? = nil,
                    xMinNormalized: Float? = nil, xMaxNormalized: Float? = nil) {
            self.mode = mode
            self.yNormalized = yNormalized
            self.xMinNormalized = xMinNormalized
            self.xMaxNormalized = xMaxNormalized
        }
    }

    public struct SkipTo: Decodable, Equatable, Sendable {
        public var atMs: Int
        public var movement: String

        public init(atMs: Int, movement: String) {
            self.atMs = atMs
            self.movement = movement
        }
    }

    public init(id: String, video: String, exercise: String, expectedReps: Int? = nil,
                expectedSetup: String? = nil, expectedCountingState: String? = nil,
                expectedRepEventsMs: [Int]? = nil, eventToleranceMs: Int? = nil,
                countTolerance: Int? = nil, expectedTracking: String? = nil, pull: String? = nil,
                bar: Bar? = nil, light: Light? = nil, tags: [String]? = nil, setup: String? = nil,
                skipTo: [SkipTo]? = nil, expectedRepsByMovement: [String: Int]? = nil) {
        self.id = id
        self.video = video
        self.exercise = exercise
        self.expectedReps = expectedReps
        self.expectedSetup = expectedSetup
        self.expectedCountingState = expectedCountingState
        self.expectedRepEventsMs = expectedRepEventsMs
        self.eventToleranceMs = eventToleranceMs
        self.countTolerance = countTolerance
        self.expectedTracking = expectedTracking
        self.pull = pull
        self.bar = bar
        self.light = light
        self.tags = tags
        self.setup = setup
        self.skipTo = skipTo
        self.expectedRepsByMovement = expectedRepsByMovement
    }

    /// The `cindy` exercise scores the whole progression; every other one is a single movement.
    public var isCindy: Bool { exercise.lowercased() == "cindy" }
}

/// A low-light model a scenario asks for. See `LightModel`.
public struct Light: Decodable, Equatable, Sendable {
    public var gain: Double?
    public var model: String?

    public init(gain: Double? = nil, model: String? = nil) {
        self.gain = gain
        self.model = model
    }
}

public enum Catalogue {

    /// The scenarios of every catalogue that exists, in the order given. A missing catalogue is
    /// reported through `warnings` and skipped, as `run_batch.py` does.
    public static func load(_ urls: [URL], warnings: inout [String]) throws -> [Scenario] {
        struct File: Decodable { var scenarios: [Scenario]? }
        var all: [Scenario] = []
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                warnings.append("no catalogue at \(url.path)")
                continue
            }
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            all.append(contentsOf: file.scenarios ?? [])
        }
        return all
    }
}

/// The movement names a scenario file uses, as `run_batch.py`'s `EXERCISES` has them.
public enum MovementNames {
    public static func exercise(_ name: String) -> Exercise? {
        switch name.lowercased() {
        case "pullup", "pull-up", "pullups", "pull-ups": return .pullup
        case "pushup", "push-up", "pushups", "push-ups": return .pushup
        case "squat", "squats": return .squat
        default: return nil
        }
    }

    /// The names a per-movement report uses, in Cindy's order.
    public static let reported: [(Exercise, String)] = [(.pullup, "pullup"), (.pushup, "pushup"), (.squat, "squat")]

    public static func reported(_ exercise: Exercise) -> String {
        reported.first { $0.0 == exercise }!.1
    }

    public static func pullVariant(_ name: String) -> PullVariant? {
        switch name.lowercased() {
        case "strict", "strict_pull_up": return .strictPullUp
        case "band_assisted", "band_assisted_pull_up": return .bandAssistedPullUp
        default: return nil
        }
    }
}
