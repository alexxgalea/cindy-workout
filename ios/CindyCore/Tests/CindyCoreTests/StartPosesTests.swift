import XCTest
import CindyCore

/// The start positions the app draws for the athlete to match.
///
/// Kotlin has no test for its table. This one proves the Swift table is the Kotlin one, by reading
/// `StartPoses.kt` and comparing every number, so the two platforms cannot show different figures;
/// and it holds the table to what its own comments promise, which nothing else checks.
final class StartPosesTests: XCTestCase {

    private struct KotlinLoop {
        var boxWidth: Float, boxHeight: Float, groundY: Float, headRadius: Float
        var barY: Float?
        var frames: [[Float]]
    }

    private func kotlinLoops() throws -> [String: KotlinLoop] {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.gradle.kts").path) {
            dir = dir.deletingLastPathComponent()
            XCTAssertNotEqual(dir.path, "/", "the repository root was not found")
            if dir.path == "/" { break }
        }
        let source = try String(contentsOf: dir.appendingPathComponent(
            "app/src/main/java/com/cindy/tracker/StartPoses.kt"), encoding: .utf8)

        var loops: [String: KotlinLoop] = [:]
        for name in ["PULL_UP", "PUSH_UP", "SQUAT"] {
            let start = try XCTUnwrap(source.range(of: "val \(name) = Loop("), name)
            let rest = source[start.upperBound...]
            let end = rest.range(of: "\n    )\n")?.lowerBound ?? rest.endIndex
            let body = String(rest[..<end])

            func number(_ key: String) -> Float {
                let r = body.range(of: "\(key) = ")!
                let tail = body[r.upperBound...]
                let text = tail.prefix { $0 != "f" && $0 != "," && $0 != "\n" }
                return Float(text)!
            }
            let barText = body[body.range(of: "barY = ")!.upperBound...].prefix { $0 != "," }
            var frames: [[Float]] = []
            var cursor = body.startIndex
            while let open = body.range(of: "floatArrayOf(", range: cursor..<body.endIndex) {
                let close = body.range(of: ")", range: open.upperBound..<body.endIndex)!
                let values = body[open.upperBound..<close.lowerBound]
                    .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
                    .map { Float($0.trimmingCharacters(in: CharacterSet(charactersIn: "f")))! }
                frames.append(values)
                cursor = close.upperBound
            }
            loops[name] = KotlinLoop(
                boxWidth: number("boxWidth"), boxHeight: number("boxHeight"),
                groundY: number("groundY"), headRadius: number("headRadius"),
                barY: barText.hasPrefix("null") ? nil : Float(barText.trimmingCharacters(in: CharacterSet(charactersIn: "f "))),
                frames: frames
            )
        }
        return loops
    }

    private var swiftLoops: [(String, StartPoses.Loop)] {
        [("PULL_UP", StartPoses.pullUp), ("PUSH_UP", StartPoses.pushUp), ("SQUAT", StartPoses.squat)]
    }

    /// every number in the table is the Kotlin one
    func testEveryNumberInTheTableIsTheKotlinOne() throws {
        let kotlin = try kotlinLoops()
        for (name, loop) in swiftLoops {
            let k = try XCTUnwrap(kotlin[name], name)
            XCTAssertEqual(loop.boxWidth, k.boxWidth, name)
            XCTAssertEqual(loop.boxHeight, k.boxHeight, name)
            XCTAssertEqual(loop.groundY, k.groundY, name)
            XCTAssertEqual(loop.headRadius, k.headRadius, name)
            XCTAssertEqual(loop.barY, k.barY, name)
            XCTAssertEqual(loop.frames, k.frames, "\(name): every joint of every keyframe")
        }
    }

    /// each loop is three keyframes of thirteen joints
    func testEachLoopIsThreeKeyframesOfThirteenJoints() {
        for (name, loop) in swiftLoops {
            XCTAssertEqual(loop.frames.count, 3, name)
            for frame in loop.frames {
                XCTAssertEqual(frame.count, StartPoses.joints * 3, "\(name): x, y, z for every joint")
            }
        }
    }

    /// left-hand joints sit at negative depth and right-hand at positive, so the figure can turn
    func testLeftHandJointsSitAtNegativeDepthAndRightHandAtPositive() {
        let left = [StartPoses.lShoulder, StartPoses.lElbow, StartPoses.lWrist,
                    StartPoses.lHip, StartPoses.lKnee, StartPoses.lAnkle]
        let right = [StartPoses.rShoulder, StartPoses.rElbow, StartPoses.rWrist,
                     StartPoses.rHip, StartPoses.rKnee, StartPoses.rAnkle]
        for (name, loop) in swiftLoops {
            for frame in loop.frames {
                for j in left { XCTAssertLessThan(frame[j * 3 + 2], 0, "\(name) joint \(j)") }
                for j in right { XCTAssertGreaterThan(frame[j * 3 + 2], 0, "\(name) joint \(j)") }
            }
        }
    }

    /// everything is drawn inside the movement's own box, and nothing below the ground
    func testEverythingIsDrawnInsideTheMovementsOwnBoxAndNothingBelowTheGround() {
        for (name, loop) in swiftLoops {
            for frame in loop.frames {
                for j in 0..<StartPoses.joints {
                    let x = frame[j * 3], y = frame[j * 3 + 1]
                    XCTAssertTrue((0...loop.boxWidth).contains(x), "\(name) joint \(j) x \(x)")
                    XCTAssertTrue((0...loop.boxHeight).contains(y), "\(name) joint \(j) y \(y)")
                    XCTAssertLessThanOrEqual(y, loop.groundY, "\(name) joint \(j) is below the ground")
                }
            }
        }
    }

    /// only the pull-up has a bar, and the held position has the hands on it
    func testOnlyThePullUpHasABarAndTheHeldPositionHasTheHandsOnIt() {
        XCTAssertNotNil(StartPoses.pullUp.barY)
        XCTAssertNil(StartPoses.pushUp.barY)
        XCTAssertNil(StartPoses.squat.barY)

        let held = StartPoses.pullUp.frames[2]
        XCTAssertEqual(held[StartPoses.lWrist * 3 + 1], StartPoses.pullUp.barY)
        XCTAssertEqual(held[StartPoses.rWrist * 3 + 1], StartPoses.pullUp.barY)
    }

    /// the bones join joints that exist
    func testTheBonesJoinJointsThatExist() {
        XCTAssertEqual(StartPoses.bones.count, 12)
        for bone in StartPoses.bones {
            XCTAssertEqual(bone.count, 2)
            XCTAssertTrue(bone.allSatisfy { (0..<StartPoses.joints).contains($0) })
        }
    }

    /// each movement finds its own loop
    func testEachMovementFindsItsOwnLoop() {
        XCTAssertEqual(StartPoses.of(.pullup).frames, StartPoses.pullUp.frames)
        XCTAssertEqual(StartPoses.of(.pushup).frames, StartPoses.pushUp.frames)
        XCTAssertEqual(StartPoses.of(.squat).frames, StartPoses.squat.frames)
    }
}
