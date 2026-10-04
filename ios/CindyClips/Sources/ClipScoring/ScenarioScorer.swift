import Foundation
import CindyCore

/// Scores a clip's frames the way `tools/video_regression/run_batch.py` does, call for call: the
/// same engines in the same order, the same checks, the same words in the failures, so the report
/// that comes out can sit next to the Python one. What differs is where the keypoints came from.
///
/// The engine is the production `WorkoutEngine` (P2's parity trace proves it matches the Kotlin
/// frame by frame), and this file adds no counting decisions of its own.
public enum ScenarioScorer {

    public static func score(_ scenario: Scenario, frames: [ClipFrame]) -> ScenarioReport {
        scenario.isCindy ? scoreCindy(scenario, frames: frames) : scoreFixed(scenario, frames: frames)
    }

    // MARK: - one movement

    private static func scoreFixed(_ scenario: Scenario, frames inferred: [ClipFrame]) -> ScenarioReport {
        let name = scenario.exercise.lowercased()
        let expectedReps = scenario.expectedReps ?? 0
        func early(_ failure: String) -> ScenarioReport {
            ScenarioReport(id: scenario.id, exercise: name, expectedReps: expectedReps, failures: [failure])
        }
        guard let exercise = MovementNames.exercise(name) else { return early("unsupported exercise '\(name)'") }

        var profile = CindyProfile()
        if let key = scenario.pull?.lowercased(), !key.isEmpty {
            guard let variant = MovementNames.pullVariant(key) else {
                return early("unsupported pull variant '\(scenario.pull ?? "")'")
            }
            profile = CindyProfile(pull: variant)
        }
        guard let first = inferred.first else { return early("no frames were read from the video") }

        var errors: [String] = []

        // Setup is validated separately from the score. Dataset labels normally include every
        // movement in a clip, while the phone deliberately does not score its two setup reps, so a
        // scoring engine sees the complete clip and a second engine verifies framing/calibration.
        let setupEngine = WorkoutEngine(fixedExercise: exercise, profile: profile)
        setupEngine.beginSetup()
        configureManualBar(setupEngine, scenario, first)
        var setup: Setup?
        for frame in inferred {
            let before = setupEngine.reps
            let blocked = setupEngine.onFrame(frame.keypoints, now: frame.timestampMs,
                                              identityStable: frame.trackingStable)
            if blocked != .none || setupEngine.reps != before {
                errors.append("workout count changed before setup completed at \(frame.timestampMs)ms")
            }
            setup = setupEngine.onSetupFrame(frame.keypoints, now: frame.timestampMs,
                                             identityStable: frame.trackingStable)
        }
        checkSetup(scenario.expectedSetup, setup?.stage, &errors)

        let engine = WorkoutEngine(fixedExercise: exercise, profile: profile)
        configureManualBar(engine, scenario, first)
        let health = TrackingHealthMonitor()
        var worst = TrackingHealth.good
        var rows: [[String: JSONValue]] = []
        var countTimes: [Int64] = []
        for frame in inferred {
            let event = engine.onFrame(frame.keypoints, now: frame.timestampMs, identityStable: frame.trackingStable)
            let d = engine.diagnostics
            health.update(exercise: engine.exercise, legible: d.poseLegible, softGain: frame.softGain,
                          now: frame.timestampMs)
            worst = worse(worst, health.health)
            if event != .none {
                countTimes.append(frame.timestampMs)
                let at = "count at \(frame.timestampMs)ms"
                if !d.scoringConfidenceAdequate { errors.append("\(at) with inadequate confidence") }
                if exercise == .pullup {
                    let pull = "pull-up count at \(frame.timestampMs)ms"
                    if !d.identityStable { errors.append("\(pull) without stable identity") }
                    if !d.barGateOpen { errors.append("\(pull) outside bar zone") }
                    if !d.deadHangSinceLastRep || !d.resetBelowBarSeen {
                        errors.append("\(pull) without a fresh reset dead hang")
                    }
                    if !d.headAboveBar { errors.append("\(pull) before head crossed bar") }
                }
            }
            rows.append([
                "timestampMs": .int(frame.timestampMs),
                "event": .string(eventName(event)),
                "count": .int(Int64(engine.reps)),
                "state": .string(engine.countingState),
                "signal": .rounded(engine.signal, places: 3),
                "learnedRange": .rounded(engine.learnedRange, places: 3),
                "minimumConfidence": .rounded(d.minimumConfidence, places: 4),
                "confidenceAdequate": .bool(d.scoringConfidenceAdequate),
                "barGateOpen": .bool(d.barGateOpen),
                "headAboveBar": .bool(d.headAboveBar),
                "resetSeen": .bool(d.resetBelowBarSeen),
                "rejection": d.rejectionReason.map(JSONValue.string) ?? .null,
                "poseLegible": .bool(d.poseLegible),
                "softGain": .rounded(frame.softGain, places: 3),
                "health": .string(health.health.rawValue.uppercased())
            ])
        }

        let tolerance = scenario.countTolerance ?? 0
        // A tolerance is an evaluation policy, not a lowered expectation: the signed error against
        // ground truth is reported regardless of whether the scenario passes.
        if abs(engine.reps - expectedReps) > tolerance {
            let suffix = tolerance != 0 ? " (tolerance \(tolerance))" : ""
            errors.append("expected \(expectedReps) reps, observed \(engine.reps)\(suffix)")
        }
        if let wanted = scenario.expectedCountingState, engine.countingState != wanted.lowercased() {
            errors.append("expected final state '\(wanted)', observed '\(engine.countingState)'")
        }
        checkEvents(scenario, countTimes, &errors)
        checkTracking(scenario, worst, &errors)

        return ScenarioReport(
            id: scenario.id, exercise: name, expectedReps: expectedReps, observedReps: engine.reps,
            setup: setup.map { stageName($0.stage) }, countTimes: countTimes, frames: rows,
            failures: errors, tags: scenario.tags ?? [], tolerance: tolerance,
            worstHealth: worst.rawValue.uppercased(), lostMs: health.lostMs)
    }

    // MARK: - the whole of Cindy

    /// A full, no-fixed-exercise Cindy attempt: setup until READY, then the real progression
    /// through pull-ups, push-ups and squats, in the app's order. `onSetupFrame` every frame while
    /// in setup, `finishSetup()` the moment it reports READY, and `onFrame` for every frame after
    /// that, never both for the same frame.
    ///
    /// Calibration is not skipped: the athlete's first two pull-ups are consumed to learn the
    /// rep-detection band and zeroed when the clock starts, so `expectedRepsByMovement` is the
    /// labelled total including them and the observed pull-ups run two lower once calibration
    /// completes. `"setup": "skip"` is the SKIP button and `skipTo` is the athlete tapping skip.
    private static func scoreCindy(_ scenario: Scenario, frames inferred: [ClipFrame]) -> ScenarioReport {
        guard let first = inferred.first else {
            return ScenarioReport(id: scenario.id, exercise: "cindy", failures: ["no frames were read from the video"])
        }
        var errors: [String] = []
        let engine = WorkoutEngine()
        let skipSetup = (scenario.setup ?? "").lowercased() == "skip"
        if !skipSetup { engine.beginSetup() }
        let order = MovementNames.reported.map { $0.0 }
        var skips: [(atMs: Int, target: Exercise)] = []
        for skip in scenario.skipTo ?? [] {
            guard let target = MovementNames.exercise(skip.movement) else {
                return ScenarioReport(id: scenario.id, exercise: "cindy",
                                      failures: ["unsupported exercise '\(skip.movement)'"])
            }
            skips.append((skip.atMs, target))
        }
        skips.sort { $0.atMs < $1.atMs }
        configureManualBar(engine, scenario, first)
        let health = TrackingHealthMonitor()
        var worst = TrackingHealth.good

        var running = skipSetup
        var setupResult: Setup?
        var rows: [[String: JSONValue]] = []
        var countTimes: [Int64] = []
        var counts: [Exercise: Int] = [:]
        var events: [Exercise: [Int64]] = [:]

        for frame in inferred {
            if !running {
                let result = engine.onSetupFrame(frame.keypoints, now: frame.timestampMs,
                                                 identityStable: frame.trackingStable)
                setupResult = result
                if result.stage == .ready {
                    engine.finishSetup()
                    running = true
                }
                continue  // this frame was SETUP; the app never also calls onFrame for it
            }

            while let skip = skips.first, frame.timestampMs >= Int64(skip.atMs) {
                skips.removeFirst()
                while order.firstIndex(of: engine.exercise)! < order.firstIndex(of: skip.target)! {
                    _ = engine.skipExercise()
                }
            }

            let event = engine.onFrame(frame.keypoints, now: frame.timestampMs, identityStable: frame.trackingStable)
            let d = engine.diagnostics
            health.update(exercise: engine.exercise, legible: d.poseLegible, softGain: frame.softGain,
                          now: frame.timestampMs)
            worst = worse(worst, health.health)

            if event == .rep || event == .exerciseDone || event == .roundDone {
                // A plain rep leaves `engine.exercise` on the movement that just scored. A done
                // event has already advanced it (the engine banks the rep under the old exercise
                // before reassigning), so the movement that just finished is the previous one.
                let finished = event == .rep ? engine.exercise : engine.exercise.previous
                counts[finished, default: 0] += 1
                events[finished, default: []].append(frame.timestampMs)
                countTimes.append(frame.timestampMs)
            }

            rows.append([
                "timestampMs": .int(frame.timestampMs), "event": .string(eventName(event)),
                "exercise": .string(engine.exercise.label), "count": .int(Int64(engine.reps)),
                "state": .string(engine.countingState), "signal": .rounded(engine.signal, places: 3),
                "rejection": d.rejectionReason.map(JSONValue.string) ?? .null,
                "poseLegible": .bool(d.poseLegible), "identityStable": .bool(d.identityStable),
                "softGain": .rounded(frame.softGain, places: 3),
                "health": .string(health.health.rawValue.uppercased())
            ])
        }

        let labelled = scenario.expectedRepsByMovement ?? [:]
        let tolerance = scenario.countTolerance ?? 0
        for (exercise, name) in MovementNames.reported {
            guard let expected = labelled[name] else { continue }
            let observed = counts[exercise] ?? 0
            if abs(observed - expected) > tolerance {
                errors.append("\(name): expected \(expected) reps, observed \(observed)"
                              + (tolerance != 0 ? " (tolerance \(tolerance))" : ""))
            }
        }
        if !running { errors.append("setup never reached READY -- no workout frames were scored") }
        checkEvents(scenario, countTimes, &errors)
        checkTracking(scenario, worst, &errors)

        var perMovement: [String: ScenarioReport.PerMovement] = [:]
        for (exercise, name) in MovementNames.reported {
            perMovement[name] = .init(expected: labelled[name] ?? 0, observed: counts[exercise] ?? 0,
                                      eventsMs: events[exercise] ?? [])
        }
        return ScenarioReport(
            id: scenario.id, exercise: "cindy", expectedReps: labelled.values.reduce(0, +),
            observedReps: counts.values.reduce(0, +), setup: setupResult.map { stageName($0.stage) },
            countTimes: countTimes, frames: rows, failures: errors, tags: scenario.tags ?? [],
            tolerance: tolerance, worstHealth: worst.rawValue.uppercased(), lostMs: health.lostMs,
            perMovement: perMovement)
    }

    // MARK: - checks shared by both

    private static func configureManualBar(_ engine: WorkoutEngine, _ scenario: Scenario, _ first: ClipFrame) {
        guard let bar = scenario.bar, (bar.mode ?? "auto").lowercased() == "manual",
              let y = bar.yNormalized, let xMin = bar.xMinNormalized, let xMax = bar.xMaxNormalized else { return }
        engine.configureManualBar(yNormalized: y, xMinNormalized: xMin, xMaxNormalized: xMax,
                                  frameWidth: first.width, frameHeight: first.height)
    }

    private static func checkSetup(_ expected: String?, _ actual: SetupStage?, _ errors: inout [String]) {
        guard let expected else { return }
        let accepted: Bool
        switch expected.lowercased() {
        case "valid": accepted = actual == .moving || actual == .ready
        case "ready": accepted = actual == .ready
        case "framing", "invalid": accepted = actual == .framing
        case "poor", "paused": accepted = actual == .poor
        default:
            errors.append("unsupported expectedSetup '\(expected)'")
            return
        }
        if !accepted {
            errors.append("expected setup '\(expected)', observed '\(actual.map(stageName) ?? "none")'")
        }
    }

    private static func checkEvents(_ scenario: Scenario, _ observed: [Int64], _ errors: inout [String]) {
        guard let expected = scenario.expectedRepEventsMs, !expected.isEmpty else { return }
        let tolerance = Int64(scenario.eventToleranceMs ?? 500)
        if expected.count != observed.count {
            errors.append("expected \(expected.count) count events, observed \(observed.count)")
            return
        }
        for (i, pair) in zip(expected, observed).enumerated() where abs(Int64(pair.0) - pair.1) > tolerance {
            errors.append("event \(i + 1): expected about \(pair.0)ms, observed \(pair.1)ms")
        }
    }

    /// A fixture may assert what the *monitor* was supposed to notice, not only what was counted:
    /// the failure it exists for is one where the score looks plausible and is quietly wrong.
    private static func checkTracking(_ scenario: Scenario, _ worst: TrackingHealth, _ errors: inout [String]) {
        if let wanted = scenario.expectedTracking, worst.rawValue.uppercased() != wanted.uppercased() {
            errors.append("expected tracking to reach \(wanted.uppercased()), observed \(worst.rawValue.uppercased())")
        }
    }

    /// The worst health seen: lost, or weak when nothing worse has been.
    private static func worse(_ worst: TrackingHealth, _ now: TrackingHealth) -> TrackingHealth {
        if now == .lost || (now == .weak && worst == .good) { return now }
        return worst
    }

    private static func eventName(_ event: RepEvent) -> String {
        switch event {
        case .none: return "NONE"
        case .rep: return "REP"
        case .undo: return "UNDO"
        case .exerciseDone: return "EXERCISE_DONE"
        case .roundDone: return "ROUND_DONE"
        }
    }

    private static func stageName(_ stage: SetupStage) -> String {
        switch stage {
        case .framing: return "framing"
        case .moving: return "moving"
        case .ready: return "ready"
        case .poor: return "poor"
        }
    }
}
