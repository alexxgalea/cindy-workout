import Foundation
import ClipScoring
#if canImport(Vision) && canImport(AVFoundation)
import CindyVision
#endif

// Scores Cindy's clips with Apple's Vision, in the shape tools/video_regression/run_batch.py
// scores them with MoveNet, and writes a report tools/video_regression/compare_reports.py reads.
//
//     swift run --package-path ios/CindyClips cindy-clips
//     swift run --package-path ios/CindyClips cindy-clips --scenarios tests/scenarios/youtube.json
//     swift run --package-path ios/CindyClips cindy-clips --video clip.mp4 --exercise pullup --expect 10
//
// A scenario whose clip is missing is skipped, with the reason, and never counted as a pass.

let usage = """
usage: cindy-clips [--scenarios FILE...] [--video FILE --exercise NAME [--expect N] [--pull VARIANT]]
                   [--report FILE] [--root DIR] [--frames] [--require-fixtures]

  --scenarios         catalogues to score (default: every tests/scenarios/*.json)
  --video             score a single clip without a catalogue
  --exercise          pullup, pushup, squat or cindy, with --video
  --expect            expected reps for --video
  --pull              strict or band_assisted, with --video
  --report            where to write the report (default: tests/reports/ios/vision-regression.json)
  --root              the repository root (default: found from the current directory)
  --frames            print every scoring frame
  --require-fixtures  exit 3 if any scenario was skipped, so a run that tested nothing is not green
"""

struct Options {
    var scenarios: [String] = []
    var video: String?
    var exercise: String?
    var expect = 0
    var pull: String?
    var report: String?
    var root: String?
    var frames = false
    var requireFixtures = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("cindy-clips: \(message)\n\(usage)\n".utf8))
    exit(64)
}

func parse(_ arguments: [String]) -> Options {
    var o = Options()
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < arguments.count else { fail("\(flag) needs a value") }
        return arguments[i]
    }
    while i < arguments.count {
        let flag = arguments[i]
        switch flag {
        case "--scenarios":
            while i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") { o.scenarios.append(arguments[i + 1]); i += 1 }
            if o.scenarios.isEmpty { fail("--scenarios needs at least one file") }
        case "--video": o.video = value(flag)
        case "--exercise": o.exercise = value(flag)
        case "--expect":
            guard let n = Int(value(flag)) else { fail("--expect needs a whole number") }
            o.expect = n
        case "--pull": o.pull = value(flag)
        case "--report": o.report = value(flag)
        case "--root": o.root = value(flag)
        case "--frames": o.frames = true
        case "--require-fixtures": o.requireFixtures = true
        case "-h", "--help":
            print(usage)
            exit(0)
        default: fail("unknown argument \(flag)")
        }
        i += 1
    }
    return o
}

/// The directory that holds tests/scenarios, looking upward from where the tool was run.
func findRoot(_ given: String?) -> URL {
    if let given { return URL(fileURLWithPath: given) }
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while true {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("tests/scenarios").path) { return dir }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { fail("no tests/scenarios above the current directory; pass --root") }
        dir = parent
    }
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
let root = findRoot(options.root)

var scenarios: [Scenario]
if let video = options.video {
    guard let exercise = options.exercise else { fail("--video requires --exercise") }
    let name = exercise.lowercased()
    guard name == "cindy" || MovementNames.exercise(name) != nil else { fail("unknown exercise '\(exercise)'") }
    scenarios = [Scenario(id: URL(fileURLWithPath: video).deletingPathExtension().lastPathComponent,
                          video: URL(fileURLWithPath: video).standardizedFileURL.path, exercise: name,
                          expectedReps: options.expect, pull: options.pull, tags: ["ad-hoc"])]
} else {
    var urls = options.scenarios.map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
    if urls.isEmpty {
        let dir = root.appendingPathComponent("tests/scenarios")
        urls = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted().map { dir.appendingPathComponent($0) }
    }
    var warnings: [String] = []
    do { scenarios = try Catalogue.load(urls, warnings: &warnings) } catch {
        fail("cannot read a catalogue: \(error)")
    }
    for warning in warnings { FileHandle.standardError.write(Data("warning: \(warning)\n".utf8)) }
}

if scenarios.isEmpty {
    FileHandle.standardError.write(Data("No scenarios to run. Add fixtures and labels first.\n".utf8))
    exit(2)
}

#if canImport(Vision) && canImport(AVFoundation)
let runner = ScenarioRunner(root: root, source: VisionClipSource())
#else
let runner = ScenarioRunner(root: root, source: nil,
                            noSourceReason: "Vision and AVFoundation exist only on macOS, and this is not one")
#endif

var reports: [ScenarioReport] = []
for scenario in scenarios {
    let report = await runner.run(scenario)
    print(RunSummary.scenarioText(report, showFrames: options.frames))
    reports.append(report)
}

let reportURL = options.report.map { URL(fileURLWithPath: $0, relativeTo: root) }
    ?? root.appendingPathComponent("tests/reports/ios/vision-regression.json")
do {
    try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ReportWriter.data(reports).write(to: reportURL)
} catch {
    fail("cannot write the report to \(reportURL.path): \(error)")
}
print(RunSummary.summaryText(reports, reportPath: reportURL.path))

let failed = reports.filter { $0.status == .failed }.count
let skipped = reports.filter { $0.status == .skipped }.count
if failed > 0 { exit(1) }
if options.requireFixtures && skipped > 0 { exit(3) }
