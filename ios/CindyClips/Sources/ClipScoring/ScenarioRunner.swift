import Foundation

/// Finds each scenario's clip, asks a frame source for its frames, and scores them.
///
/// A scenario that cannot be run is *skipped, with the reason*: its clip is not there, or this
/// machine has no pose source. A green run therefore never means that clips nobody could provide
/// were tested, which is the rule the Android job follows too.
public struct ScenarioRunner {
    public let root: URL
    public let source: ClipFrameSource?
    /// Why there is no `source`, for the skipped report.
    public let noSourceReason: String

    public init(root: URL, source: ClipFrameSource?, noSourceReason: String = "no pose source on this platform") {
        self.root = root
        self.source = source
        self.noSourceReason = noSourceReason
    }

    public func videoURL(for scenario: Scenario) -> URL {
        let path = scenario.video
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    public func run(_ scenario: Scenario) async -> ScenarioReport {
        let url = videoURL(for: scenario)
        // The clip is looked for before the source is asked for anything, so a machine with
        // neither reports the missing clip, which is the thing to fix.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .skipped(scenario, because: "missing fixture: \(url.path)")
        }
        guard let source else { return .skipped(scenario, because: noSourceReason) }
        do {
            let frames = try await source.frames(of: url, light: scenario.light)
            return ScenarioScorer.score(scenario, frames: frames)
        } catch let unavailable as ClipUnavailable {
            return .skipped(scenario, because: unavailable.reason)
        } catch let unreadable as ClipUnreadable {
            return ScenarioReport(id: scenario.id, exercise: scenario.exercise.lowercased(),
                                  expectedReps: scenario.expectedReps ?? 0,
                                  failures: [unreadable.reason], tags: scenario.tags ?? [])
        } catch {
            return ScenarioReport(id: scenario.id, exercise: scenario.exercise.lowercased(),
                                  expectedReps: scenario.expectedReps ?? 0,
                                  failures: ["\(error)"], tags: scenario.tags ?? [])
        }
    }
}

/// The console text of a run, as `run_batch.py` prints it, with the skipped scenarios said first
/// and counted on their own.
public enum RunSummary {

    public static func scenarioText(_ r: ScenarioReport, showFrames: Bool) -> String {
        var lines = ["", "Scenario: \(r.id)  [\(r.exercise)]"]
        if r.status == .skipped {
            lines.append("  Status:        SKIPPED -- \(r.skipReason ?? "")")
            return lines.joined(separator: "\n")
        }
        lines.append("  Expected reps: \(r.expectedReps)")
        lines.append("  Counted reps:  \(r.observedReps)")
        lines.append("  Signed error:  \(signed(r.signedError))"
                     + (r.tolerance != 0 ? " (tolerance ±\(r.tolerance))" : ""))
        lines.append("  Setup:         \(r.setup ?? "None")")
        if !r.countTimes.isEmpty {
            lines.append("  Counted at:    " + r.countTimes.map { "\($0)ms" }.joined(separator: ", "))
        }
        lines.append("  Status:        \(r.status == .passed ? "OK" : "FAIL")")
        for failure in r.failures { lines.append("    - \(failure)") }
        if showFrames {
            for frame in r.frames {
                lines.append("    \(text(frame["timestampMs"]))ms \(text(frame["event"])) n=\(text(frame["count"]))"
                             + " \(text(frame["state"])) sig=\(text(frame["signal"])) rej=\(text(frame["rejection"]))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Metrics by category, valid and must-not-count clips apart, and the counts a CI step reads.
    public static func summaryText(_ reports: [ScenarioReport], reportPath: String) -> String {
        var out: [String] = []
        let ran = reports.filter { $0.status != .skipped }
        // With nothing run there is nothing to measure, and a header over nothing would read as a
        // clean result.
        if !ran.isEmpty {
            out += ["", String(repeating: "=", count: 62),
                    "Metrics by category — valid and must-not-count clips stay separate,",
                    "because blending them produces a flattering number that means nothing.",
                    String(repeating: "=", count: 62)]
        }
        for category in ["clean-valid", "difficult-but-valid", "must-not-count"] {
            let group = ran.filter { $0.category == category }
            if group.isEmpty { continue }
            let exact = group.filter { $0.signedError == 0 }.count
            let mae = Double(group.map { abs($0.signedError) }.reduce(0, +)) / Double(group.count)
            out.append("")
            out.append("  \(category)  (\(group.count) clip(s))")
            out.append("    exact count:        \(exact)/\(group.count)")
            out.append("    mean absolute error: \(String(format: "%.2f", mae)) reps")
            if category == "must-not-count" {
                let falsePositives = group.map { $0.observedReps }.reduce(0, +)
                out.append("    false positives:     \(falsePositives)"
                           + (falsePositives != 0 ? "  <-- MUST BE ZERO" : "  (clean)"))
            }
            let under = group.filter { $0.signedError < 0 }.map { $0.id }
            let over = group.filter { $0.signedError > 0 }.map { $0.id }
            if !under.isEmpty { out.append("    under-counting:      " + under.joined(separator: ", ")) }
            if !over.isEmpty { out.append("    over-counting:       " + over.joined(separator: ", ")) }
        }
        let passed = reports.filter { $0.status == .passed }.count
        let failed = reports.filter { $0.status == .failed }.count
        let skipped = reports.filter { $0.status == .skipped }.count
        out.append("")
        out.append("\(passed) passed, \(failed) failed, \(skipped) skipped of \(reports.count) scenario(s). Report: \(reportPath)")
        if skipped > 0 {
            out.append("Skipped scenarios were NOT run: a skipped scenario is not a pass.")
        }
        return out.joined(separator: "\n")
    }

    private static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    private static func text(_ value: JSONValue?) -> String {
        switch value {
        case .int(let i)?: return String(i)
        case .double(let d)?: return String(d)
        case .string(let s)?: return s
        case .bool(let b)?: return b ? "True" : "False"
        default: return "None"
        }
    }
}
