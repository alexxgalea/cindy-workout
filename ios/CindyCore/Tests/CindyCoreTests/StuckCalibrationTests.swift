import XCTest
import CindyCore

/// Calibration that never finished, though the athlete was doing pull-ups on the wall bars.
///
/// Mirrors `StuckCalibrationTest.kt`, and asks for more: the Kotlin engine's own moment of READY on
/// each recording, to the millisecond, so any drift between the two engines on a real session shows
/// here as a different number rather than as a pass.
///
/// Each `tests/traces/calibration_stuck_*.csv` is the setup part of a real session written by a
/// debug build on a Huawei P40, from the first frame until a few seconds after the fixed engine
/// calibrates. The phone stayed at 0 of 2 and said "Get on the bar" while the athlete pulled up.
/// `calibration_ok_1637.csv` is a session that calibrated, as the control.
final class StuckCalibrationTests: XCTestCase {

    /// Where the Kotlin engine reaches READY on each recording, in the trace's clock.
    private let kotlinReadyAt: [(String, Int64)] = [
        ("calibration_stuck_1635", 20_891),
        ("calibration_stuck_1643", 32_286),
        ("calibration_stuck_1644", 39_315),
        ("calibration_stuck_1651", 30_643),
        ("calibration_ok_1637", 24_252),
    ]

    /// a bar learned from a sliver of a grip does not stop the athlete calibrating
    func testEachRecordedSessionCalibratesAtTheMomentTheKotlinEngineDid() throws {
        for (name, expected) in kotlinReadyAt {
            let calibratedAt = try calibratedAt(name)
            XCTAssertEqual(calibratedAt, expected, "\(name): the Kotlin engine calibrated at \(expected) ms")
        }
    }

    /// Replays a trace as the app does: setup frames, with a recalibration where one happened.
    private func calibratedAt(_ name: String) throws -> Int64? {
        let url = try repositoryRoot().appendingPathComponent("tests/traces/\(name).csv")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").dropFirst()
        let engine = WorkoutEngine()
        engine.beginSetup()
        var at: Int64?
        for line in lines {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let ms = Int64(f[1])!
            if f[0] == "RECALIBRATE" {
                engine.recalibrate()
                continue
            }
            let keypoints = (0..<17).map { i in
                Keypoint(x: Float(f[3 + 3 * i])!, y: Float(f[4 + 3 * i])!, score: Float(f[5 + 3 * i])!)
            }
            let setup = engine.onSetupFrame(keypoints, now: ms, identityStable: f[2] == "1")
            if at == nil, setup.stage == .ready, setup.reps >= 2 { at = ms }
        }
        return at
    }

    private func repositoryRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.gradle.kts").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate the repository root")
    }
}
